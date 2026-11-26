import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/live_activity_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/ui/chat/activity_strip.dart';
import 'package:agy_go/ui/chat/chat_list.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubConnection extends ActiveConnectionController {
  _StubConnection(this._conn);
  final HostConnection _conn;

  @override
  Future<HostConnection?> build() async => _conn;
}

class _SeededChatController extends ChatController {
  _SeededChatController(this._initial);
  final ChatState _initial;

  @override
  ChatState build() => _initial;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Turn telemetry parsing & health classification', () {
    test('parseRetryFromLogLine parses 429, network resets, attempts, and delays while ignoring routine runtime logs', () {
      final now = DateTime(2026, 11, 26, 16, 45, 0);

      final r429 = parseRetryFromLogLine(
        '[stderr] WARN HTTP 429 Too Many Requests: retrying attempt 2/5 in 4s',
        now: now,
      );
      expect(r429, isNotNull);
      expect(r429!.rateLimited, isTrue);
      expect(r429.attempt, 2);
      expect(r429.maxAttempts, 5);
      expect(r429.retryInSeconds, 4);
      expect(r429.compactPillLabel(), '限流重试 (2/5)…');
      expect(r429.summary, contains('429'));
      expect(r429.summary, contains('第 2/5 次'));
      expect(r429.summary, contains('4s'));

      final rNet = parseRetryFromLogLine(
        '[stderr] stream error: connection reset by peer, retry 1/3 after 2000ms',
        now: now,
      );
      expect(rNet, isNotNull);
      expect(rNet!.rateLimited, isFalse);
      expect(rNet.attempt, 1);
      expect(rNet.maxAttempts, 3);
      expect(rNet.retryInSeconds, 2);
      expect(rNet.compactPillLabel(), '网络重试 (1/3)…');

      // Benign lifecycle logs must NOT trigger false retry alerts.
      expect(
        parseRetryFromLogLine('[system] [runtime] launching (native_bionic)'),
        isNull,
      );
      expect(
        parseRetryFromLogLine('[system] [bridge] Flutter client attached'),
        isNull,
      );
      expect(
        parseRetryFromLogLine('[stderr] loaded workspace successfully'),
        isNull,
      );
    });

    test('parseRetryFromUnknownUpdate and parseRetryFromRawNotification detect structured retry events', () {
      final unknown = parseRetryFromUnknownUpdate(
        const UnknownSessionUpdate(
          kind: 'retry',
          raw: {
            'sessionUpdate': 'retry',
            'message': 'temporary network timeout, retrying',
            'attempt': 3,
            'maxAttempts': 5,
            'retryAfterMs': 3500,
          },
        ),
      );
      expect(unknown, isNotNull);
      expect(unknown!.attempt, 3);
      expect(unknown.maxAttempts, 5);
      expect(unknown.retryInSeconds, 4);
      expect(unknown.compactPillLabel(), '网络重试 (3/5)…');

      final rawNotif = parseRetryFromRawNotification(
        const AcpRawNotification(
          method: r'$/progress',
          params: {
            'value': {
              'title': 'Retrying request',
              'message': '503 Service Unavailable, backoff 5s',
            },
          },
        ),
      );
      expect(rawNotif, isNotNull);
      expect(rawNotif!.retryInSeconds, 5);
    });

    test('deriveTurnHealth separates active thinking, quiet waiting, retrying, and prolonged silence', () {
      final t0 = DateTime(2026, 11, 26, 16, 0, 0);

      // Active thinking (3s ago, 420 chars)
      final active = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0.add(const Duration(seconds: 20)),
        phase: TurnLivePhase.thinking,
        activeRetry: null,
        thoughtChars: 420,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 23)),
      );
      expect(active.tone, TurnHealthTone.active);
      expect(active.pillText, '思考中 · 420字');
      expect(active.showAlertBanner, isFalse);

      // Quiet wait (28s ago)
      final waiting = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0,
        phase: TurnLivePhase.thinking,
        activeRetry: null,
        thoughtChars: 420,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 28)),
      );
      expect(waiting.tone, TurnHealthTone.waiting);
      expect(waiting.pillText, '深度思考中 · 28s前更新');
      expect(waiting.showAlertBanner, isFalse);

      // Prolonged silence (95s ago, no active tool) -> suspectedStall + alert banner!
      final stalled = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0,
        phase: TurnLivePhase.thinking,
        activeRetry: null,
        thoughtChars: 420,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 95)),
      );
      expect(stalled.tone, TurnHealthTone.suspectedStall);
      expect(stalled.pillText, '1m35s无新输出');
      expect(stalled.showAlertBanner, isTrue);

      // Explicit retry notice -> retrying + alert banner!
      final retry = parseRetryFromLogLine(
        '[stderr] 429 rate limit retrying attempt 2/5 in 4s',
        now: t0.add(const Duration(seconds: 40)),
      )!;
      final retrying = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0.add(const Duration(seconds: 40)),
        phase: TurnLivePhase.retrying,
        activeRetry: retry,
        thoughtChars: 420,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 43)),
      );
      expect(retrying.tone, TurnHealthTone.retrying);
      expect(retrying.pillText, '限流重试 (2/5)…');
      expect(retrying.showAlertBanner, isTrue);
    });

    test('tailPreviewLines and latestThoughtHeadline always surface the newest thinking lines', () {
      const multiLine =
          'Line 1 old\nLine 2 old\n\nLine 3 middle\n**Line 4 newer**\nLine 5 latest';
      expect(latestThoughtHeadline(multiLine), 'Line 5 latest');
      expect(
        tailPreviewLines(multiLine, maxLines: 2),
        '**Line 4 newer**\nLine 5 latest',
      );
    });
  });

  group('ChatController live retry detection & recovery', () {
    test('captures mid-turn retry notification, updates LiveActivity, and clears automatically on next chunk', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      final promptGate = Completer<void>();
      agent.onRequest('initialize', (_) async => {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.6.0'},
        'agentCapabilities': {'loadSession': true},
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async => {'sessionId': 'sess-live'});
      agent.onRequest('session/prompt', (_) async {
        await promptGate.future;
        return {'stopReason': 'end_turn'};
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.ssh('remote-1'),
        label: 'Test Host',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
        ],
      );
      addTearDown(container.dispose);

      container.read(chatProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final sendFuture = container.read(chatProvider.notifier).send('测试重试状态');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 1. Agent emits a non-standard retry notification mid-turn!
      await agent.sendNotification(r'$/progress', {
        'message': 'HTTP 429 rate limit, retrying attempt 2/5 in 4s',
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final duringRetry = container.read(chatProvider);
      expect(duringRetry.activeRetry, isNotNull);
      expect(duringRetry.activeRetry!.rateLimited, isTrue);
      expect(duringRetry.activeRetry!.attempt, 2);
      expect(duringRetry.retryCount, 1);
      expect(duringRetry.livePhase, TurnLivePhase.retrying);

      // Background Live Activity capsule also surfaces the retry state!
      final livePayload = deriveLiveActivity(
        chat: duringRetry,
        phone: const PhoneControlState(),
        sessionTitle: '测试会话',
        settings: const AppSettings(),
        foreground: false,
      );
      expect(livePayload?.chip, '重试中');

      // 2. Agent resumes streaming thought chunks -> retry banner clears automatically!
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-live',
        'update': {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': '已恢复连接，继续分析任务。'},
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final recovered = container.read(chatProvider);
      expect(recovered.activeRetry, isNull);
      expect(recovered.livePhase, TurnLivePhase.thinking);
      expect(recovered.thoughtChars, greaterThan(0));
      expect(
        recovered.turnEvents.any((e) => e.label.contains('网络已恢复')),
        isTrue,
      );

      promptGate.complete();
      await sendFuture;
      expect(container.read(chatProvider).isBusy, isFalse);
    });

    test('sendQueuedNow waits through agy acp "running prompt is being cancelled" window and delivers without duplicating user bubble', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      var cancelling = false;
      Completer<Map<String, Object?>>? runningPrompt;
      var rejectedCount = 0;

      agent.onRequest('initialize', (_) async => {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.6.0'},
        'agentCapabilities': {'loadSession': true},
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async => {'sessionId': 'sess-cancel-race'});
      agent.onNotification('session/cancel', (_) {
        // Simulate real agy acp taking 650ms (past the 400ms pre-wait) to finish cancelling!
        cancelling = true;
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          cancelling = false;
          if (runningPrompt != null && !runningPrompt!.isCompleted) {
            runningPrompt!.complete({'stopReason': 'cancelled'});
          }
        });
      });

      agent.onRequest('session/prompt', (params) async {
        final sid = params['sessionId']! as String;
        final text = ((params['prompt'] as List).first as Map)['text'] as String;
        if (cancelling) {
          rejectedCount++;
          throw AcpRpcException(
            code: -32603,
            message:
                "Can't add this prompt to session $sid: the running prompt is being cancelled; wait for it to finish, then send this prompt again",
          );
        }
        if (text == '长思考任务') {
          runningPrompt = Completer<Map<String, Object?>>();
          return runningPrompt!.future;
        }
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': '已收到立即发送：$text'},
          },
        });
        return {'stopReason': 'end_turn'};
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机引擎',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
        ],
      );
      addTearDown(container.dispose);

      container.read(chatProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final turn1 = container.read(chatProvider.notifier).send('长思考任务');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Queue follow-up then tap 「立即发送」.
      await container.read(chatProvider.notifier).send('怎么样了这么久了');
      expect(container.read(chatProvider).queuedMessages, ['怎么样了这么久了']);

      await container.read(chatProvider.notifier).sendQueuedNow(0);
      await turn1;

      final after = container.read(chatProvider);
      expect(rejectedCount, greaterThanOrEqualTo(1));
      expect(after.error, isNull);
      expect(after.isBusy, isFalse);
      // User bubble for 「怎么样了这么久了」 must appear EXACTLY once!
      final userBubbles = after.transcript.items
          .whereType<UserTranscriptItem>()
          .where((u) => u.text == '怎么样了这么久了')
          .toList();
      expect(userBubbles.length, 1);
      expect(
        (after.transcript.items.last as AssistantTranscriptItem).text,
        '已收到立即发送：怎么样了这么久了',
      );
    });
  });

  group('Retry banner, stall pill, diagnostics sheet & live thinking tail UI', () {
    testWidgets('ActivityStrip + TurnAlertBanner render retry state and open live diagnostics sheet', (tester) async {
      final now = DateTime.now();
      final retry = parseRetryFromLogLine(
        '[stderr] connection reset by peer, retrying attempt 2/5 in 4s',
        now: now,
      )!;
      final seeded = ChatState(
        sessionId: 's-retry',
        isSending: true,
        turnStartedAt: now.subtract(const Duration(minutes: 2)),
        lastActivityAt: now,
        livePhase: TurnLivePhase.retrying,
        thoughtChars: 640,
        activeRetry: retry,
        retryCount: 2,
        turnEvents: [
          TurnActivityLogEntry(
            timestamp: now,
            label: retry.summary,
            detail: retry.rawMessage,
            isWarning: true,
          ),
        ],
        turnLogs: const ['connection reset by peer, retrying attempt 2/5 in 4s'],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatProvider.overrideWith(() => _SeededChatController(seeded)),
          ],
          child: const AgyGoApp(
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TurnAlertBanner(),
                  ActivityStrip(inline: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('网络重试 (2/5)…'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);

      // Tap the ActivityStrip to open the live diagnostics & logs sheet!
      await tester.tap(find.text('网络重试 (2/5)…'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('实时运行状态与进度'), findsOneWidget);
      expect(find.text('实时健康度（判断正常运行 / 重试 / 卡住）'), findsOneWidget);
      expect(find.text('引擎重试原文'), findsOneWidget);
      expect(find.text('中止当前卡顿并重发上一条消息'), findsOneWidget);
    });

    testWidgets('ChatList shows live thinking tail (not line 1) and footer status below finished tools', (tester) async {
      final now = DateTime.now();
      final seeded = ChatState(
        sessionId: 's-think',
        isSending: true,
        turnStartedAt: now.subtract(const Duration(minutes: 3)),
        lastActivityAt: now.subtract(const Duration(seconds: 95)),
        livePhase: TurnLivePhase.thinking,
        thoughtChars: 240,
        transcript: ChatTranscript(
          items: [
            UserTranscriptItem(id: 'u1', timestamp: now, text: '修复汉化问题'),
            AssistantTranscriptItem(
              id: 'a1',
              timestamp: now,
              isStreaming: true,
              thought:
                  'Old line 1 from 20 minutes ago\nOld line 2\nOld line 3\nLatest active thought line right now',
              toolCalls: const [
                AcpToolCall(
                  toolCallId: 'tc1',
                  title: '读取 MapInfos.json',
                  kind: AcpToolKind.read,
                  status: AcpToolStatus.completed,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatProvider.overrideWith(() => _SeededChatController(seeded)),
          ],
          child: AgyGoApp(
            home: Scaffold(
              body: ChatList(
                scrollController: ScrollController(),
                bottomInset: 80,
                onPickSuggestion: (_) {},
                onEditDraft: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Shows latest thought line instead of staying stuck on line 1, AND shows stall warning below tool!
      expect(find.textContaining('Latest active thought line right now'), findsWidgets);
      expect(find.textContaining('未收到模型新输出'), findsOneWidget);
    });
  });
}

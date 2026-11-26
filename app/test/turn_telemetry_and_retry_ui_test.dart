import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/live_activity_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/state/sessions_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/state/workspaces_state.dart';
import 'package:agy_go/ui/chat/activity_strip.dart';
import 'package:agy_go/ui/chat/chat_list.dart';
import 'package:agy_go/ui/chat/tool_call_card.dart';
import 'package:agy_go/ui/chat/tool_format.dart';
import 'package:agy_go/ui/common/status_dot.dart';
import 'package:agy_go/ui/shell/sessions_drawer.dart';
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

    test('deriveTurnHealth reflects native thinking heading, factual waiting, retrying, and prolonged silence without guessing', () {
      final t0 = DateTime(2026, 11, 26, 16, 0, 0);

      // Active thinking with native heading from agent_thought_chunk (3s ago)
      final active = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0.add(const Duration(seconds: 20)),
        phase: TurnLivePhase.thinking,
        activeRetry: null,
        thoughtChars: 420,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        liveThoughtHeadline: 'Checking ACP status handling',
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 23)),
      );
      expect(active.tone, TurnHealthTone.active);
      expect(active.pillText, '思考 · Checking ACP status handling');
      expect(active.detailHeadline, contains('420字'));
      expect(active.showAlertBanner, isFalse);

      // Quiet wait (28s ago) -> factual elapsed gap, never guesses "深度思考中"
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
      expect(waiting.pillText, '思考中 · 28s');
      expect(waiting.pillText, isNot(contains('深度思考')));
      expect(waiting.showAlertBanner, isFalse);

      // Prolonged silence (95s ago, no active tool) -> factual suspectedStall + alert banner!
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
      expect(stalled.pillText, '思考中 · 1m35s无新事件');
      expect(stalled.detailHeadline, contains('未收到新思考片段'));
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

    test('tailPreviewLines and latestThoughtHeadline prefer Gemini native bold/markdown headers and fall back to newest prose line', () {
      const withHeading =
          'Line 1 old\n**Inspecting status bar**\nChecking lines 120 to 160 in chat_screen.dart';
      expect(latestThoughtHeadline(withHeading), 'Inspecting status bar');
      expect(
        tailPreviewLines(withHeading, maxLines: 2),
        '**Inspecting status bar**\nChecking lines 120 to 160 in chat_screen.dart',
      );

      const plainProse = 'Line 1 old\nLine 2 middle\nLine 3 latest';
      expect(latestThoughtHeadline(plainProse), 'Line 3 latest');
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
      expect(find.text('实时状态（原生事件 / 重试 / 超时监测）'), findsOneWidget);
      expect(find.text('引擎重试原文'), findsOneWidget);
      expect(find.text('中止当前卡顿并重发上一条消息'), findsOneWidget);
    });

    testWidgets('ChatList shows live thinking tail (not line 1) and factual silence warning below finished tools', (tester) async {
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

      // Shows latest thought line instead of staying stuck on line 1, AND shows factual silence warning!
      expect(find.textContaining('Latest active thought line right now'), findsWidgets);
      expect(find.textContaining('未收到新思考片段'), findsOneWidget);
    });

    test('TurnSpeedTracker, resolveNativeHeaderStatus, extractNativeStatusUpdate & deriveTurnHealth report strictly native signals', () {
      expect(estimateTokenCount('你好世界hello'), greaterThan(3));
      expect(formatTokensPerSecond(48.64), '48.6 tok/s');
      expect(formatTokensPerSecond(48.64, compact: true), '49 tok/s');
      expect(formatTokensPerSecond(125.4), '125 tok/s');

      final tracker = TurnSpeedTracker();
      final t0 = DateTime(2026, 11, 26, 17, 0, 0);
      tracker.recordChunk('First chunk of output text here for testing speed.', t0);
      tracker.recordChunk('Second chunk of output text here for testing speed.', t0.add(const Duration(milliseconds: 500)));
      // Simulate a 20-second tool pause — tracker must cap active gap at 1.5s!
      tracker.recordChunk('Third chunk after tool execution finishes.', t0.add(const Duration(seconds: 21)));

      final live = tracker.liveTokensPerSecond(t0.add(const Duration(seconds: 21, milliseconds: 200)));
      expect(live, isNotNull);
      expect(live!, greaterThan(5));

      final serverFinal = tracker.finalize(
        usage: const AcpUsageInfo(outputTokens: 160, thoughtTokens: 40),
        now: t0.add(const Duration(seconds: 21, milliseconds: 200)),
      );
      expect(serverFinal, isNotNull);
      expect(serverFinal!.tokens, 200);
      expect(serverFinal.estimated, isFalse);
      // Active generation time is 0.5s + 1.5s = 2.0s (NOT 21s!) -> ~100 tok/s
      expect(serverFinal.generationSeconds, closeTo(2.0, 0.05));
      expect(serverFinal.tokensPerSecond, closeTo(100.0, 5.0));

      final estFinal = tracker.finalize(now: t0.add(const Duration(seconds: 21, milliseconds: 200)));
      expect(estFinal, isNotNull);
      expect(estFinal!.estimated, isTrue);

      // Native tool label formatting prefers model's own rawInput.toolAction / toolSummary.
      const activeTool = AcpToolCall(
        toolCallId: 'tc-native',
        name: 'read_file',
        title: 'read_file',
        kind: AcpToolKind.read,
        status: AcpToolStatus.inProgress,
        rawInput: {
          'Path': '/repo/lib/main.dart',
          'toolAction': 'Viewing lib/main.dart',
          'toolSummary': 'View lib/main.dart',
        },
      );
      expect(
        formatNativeToolLiveStatus(activeTool, workspaceCwd: '/repo'),
        'Viewing lib/main.dart',
      );
      expect(
        resolveNativeHeaderStatus(
          phase: TurnLivePhase.working,
          activeToolStatus: formatNativeToolLiveStatus(
            activeTool,
            workspaceCwd: '/repo',
          ),
        ),
        'Viewing lib/main.dart',
      );

      // Native header status shows verbatim engine status, thought heading, or honest 等待响应.
      expect(
        resolveNativeHeaderStatus(
          phase: TurnLivePhase.working,
          nativeStatusLabel: '压缩上下文中',
        ),
        '压缩上下文中',
      );
      expect(
        resolveNativeHeaderStatus(
          phase: TurnLivePhase.thinking,
          liveThoughtHeadline: 'Planning patch for chat_state.dart',
        ),
        '思考 · Planning patch for chat_state.dart',
      );
      expect(
        resolveNativeHeaderStatus(phase: TurnLivePhase.waiting),
        '等待响应',
      );

      // extractNativeStatusUpdate returns verbatim engine messages and explicit clears without keyword guessing.
      final verbatim = extractNativeStatusUpdate(
        kindOrMethod: 'agent_status',
        payload: {'message': 'Compacting conversation history'},
      );
      expect(verbatim?.text, 'Compacting conversation history');
      expect(verbatim?.clear, isFalse);

      final compactStart = extractNativeStatusUpdate(
        kindOrMethod: 'compaction_update',
        payload: {'status': 'in_progress'},
      );
      expect(compactStart?.text, '压缩上下文中');
      expect(compactStart?.clear, isFalse);

      final compactDone = extractNativeStatusUpdate(
        kindOrMethod: 'compaction_update',
        payload: {'status': 'completed'},
      );
      expect(compactDone?.clear, isTrue);

      final progressReport = extractNativeStatusUpdate(
        kindOrMethod: r'$/progress',
        payload: {
          'value': {
            'kind': 'report',
            'title': 'Indexing workspace',
            'message': '18/40 files',
          },
        },
      );
      expect(progressReport?.text, 'Indexing workspace · 18/40 files');

      final progressEnd = extractNativeStatusUpdate(
        kindOrMethod: r'$/progress',
        payload: {
          'value': {'kind': 'end'},
        },
      );
      expect(progressEnd?.clear, isTrue);

      // Factual trajectoryStateUpdate log parsing
      expect(
        parseTrajectoryStateFromLogLine(
          '[stderr] RAW WS MSG: {"trajectoryStateUpdate":{"state":"STATE_WAITING_FOR_TASKS"}}',
        )?.statusText,
        '等待后台任务',
      );
      expect(
        parseTrajectoryStateFromLogLine(
          '[stderr] RAW WS MSG: {"trajectoryStateUpdate":{"state":"STATE_FULLY_IDLE"}}',
        )?.clear,
        isTrue,
      );

      // deriveTurnHealth surfaces active tool label verbatim without inventing 分析中 / 编辑中 prefixes.
      final toolHealth = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0,
        phase: TurnLivePhase.working,
        activeRetry: null,
        thoughtChars: 0,
        answerChars: 0,
        hasActiveTool: true,
        activeToolLabel: 'Viewing lib/main.dart',
        activePlanLabel: null,
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(toolHealth.pillText, 'Viewing lib/main.dart');

      final speedThinkHealth = deriveTurnHealth(
        startedAt: t0,
        lastActivityAt: t0,
        phase: TurnLivePhase.thinking,
        activeRetry: null,
        thoughtChars: 300,
        answerChars: 0,
        hasActiveTool: false,
        activeToolLabel: null,
        activePlanLabel: null,
        liveTokensPerSecond: 46.2,
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(speedThinkHealth.pillText, '思考中 · 46 tok/s');

      // Command output timestamp header stripping
      expect(
        stripAgyCommandResultHeader(
          'Created At: 2026-11-26T04:00:00Z\nCompleted At: 2026-11-26T04:00:02Z\nAll tests passed!',
        ),
        'All tests passed!',
      );
    });

    test('ChatController does not fabricate 分析工具结果 after tool finishes and applies compaction + late background tool patches', () async {
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
      agent.onRequest('session/new', (_) async => {'sessionId': 'sess-native'});
      agent.onRequest('session/prompt', (_) async {
        await promptGate.future;
        return {'stopReason': 'end_turn'};
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: 'Test',
        client: client,
        initResult: init,
        defaultCwd: '/repo',
      );
      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
        ],
      );
      addTearDown(container.dispose);

      container.read(chatProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final turn = container.read(chatProvider.notifier).send('检查代码');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 1. Active tool starts with native toolAction
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tc-1',
          'name': 'read_file',
          'title': 'read_file',
          'kind': 'read',
          'status': 'in_progress',
          'rawInput': {
            'Path': '/repo/lib/app.dart',
            'toolAction': 'Reading app.dart',
            'toolSummary': 'Read app.dart',
          },
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(chatProvider).livePhase, TurnLivePhase.working);

      // 2. Tool completes -> MUST NOT fabricate "分析工具结果"! Goes cleanly to waiting.
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'tc-1',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(chatProvider).livePhase, TurnLivePhase.waiting);
      expect(container.read(chatProvider).liveStatusLabel, isNull);

      // 3. Native compaction_update sets status and clears cleanly when completed.
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'compaction_update',
          'status': 'in_progress',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(chatProvider).liveStatusLabel, '压缩上下文中');

      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'compaction_update',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(chatProvider).liveStatusLabel, isNull);

      // 4. Background tool still running when prompt ends, then patched after end_turn!
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tc-bg',
          'name': 'run_command',
          'title': 'Running tests',
          'kind': 'execute',
          'status': 'in_progress',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      promptGate.complete();
      await turn;
      expect(container.read(chatProvider).isBusy, isFalse);

      // Late patch for known background tool updates transcript even after end_turn.
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-native',
        'update': {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'tc-bg',
          'status': 'completed',
          'rawOutput': 'Created At: 2026-11-26T04:00:00Z\nCompleted At: 2026-11-26T04:00:03Z\nPASS',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final lastAssistant =
          container.read(chatProvider).transcript.items.last as AssistantTranscriptItem;
      expect(lastAssistant.toolCallById('tc-bg')?.status, AcpToolStatus.completed);
      expect(lastAssistant.toolCallById('tc-bg')?.rawOutput, contains('PASS'));
    });

    testWidgets('ToolCallCard renders native toolAction and strips Created At command headers', (tester) async {
      const tc = AcpToolCall(
        toolCallId: 'tc-cmd',
        name: 'run_command',
        title: 'run_command',
        kind: AcpToolKind.execute,
        status: AcpToolStatus.completed,
        rawInput: {
          'CommandLine': 'flutter test',
          'toolAction': 'Running tests',
          'toolSummary': 'Run unit test suite',
        },
        rawOutput:
            'Created At: 2026-11-26T04:00:00Z\nCompleted At: 2026-11-26T04:00:02Z\n00:02 +73: All tests passed!',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: AgyGoApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(12),
                child: ToolCallCard(toolCall: tc, workspaceCwd: '/repo'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Completed card displays native toolSummary + command without guessed verb override.
      expect(find.text('Run unit test suite'), findsOneWidget);
      expect(find.text('flutter test'), findsOneWidget);

      // Expand to inspect cleaned command output (no Created At / Completed At boilerplate).
      await tester.tap(find.text('Run unit test suite'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('00:02 +73: All tests passed!'), findsOneWidget);
      expect(find.textContaining('Created At:'), findsNothing);
    });

    test('switching conversations and workspaces keeps background turns alive and isolates cancel()', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      var nextSessionNum = 0;
      final promptCompleters = <String, Completer<Map<String, Object?>>>{};
      final cancelledSessions = <String>[];
      var loadCalls = 0;

      agent.onRequest('initialize', (_) async => {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.6.0'},
        'agentCapabilities': {'loadSession': true},
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/load', (_) async {
        loadCalls++;
        return <String, Object?>{};
      });
      agent.onRequest('session/new', (_) async {
        nextSessionNum++;
        return {'sessionId': 'sess-$nextSessionNum'};
      });
      agent.onNotification('session/cancel', (params) {
        final sid = params['sessionId'] as String?;
        if (sid != null) {
          cancelledSessions.add(sid);
          final c = promptCompleters[sid];
          if (c != null && !c.isCompleted) {
            c.complete({'stopReason': 'cancelled'});
          }
        }
      });
      agent.onRequest('session/prompt', (params) {
        final sid = params['sessionId']! as String;
        final c = Completer<Map<String, Object?>>();
        promptCompleters[sid] = c;
        return c.future;
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.ssh('remote-bg'),
        label: 'Test Host',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws-a',
      );

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
        ],
      );
      addTearDown(container.dispose);

      final wsCtrl = container.read(workspacesProvider.notifier);
      final wsA = await wsCtrl.add('/tmp/ws-a', title: '工作区A');
      final wsB = await wsCtrl.add('/tmp/ws-b', title: '工作区B');
      await wsCtrl.select(wsA.id);

      container.read(chatProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 1. Start turn in Workspace A (sess-1)
      final turnA = container.read(chatProvider.notifier).send('后台任务A');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(container.read(chatProvider).sessionId, 'sess-1');
      expect(container.read(chatProvider).isBusy, isTrue);

      // 2. Switch workspace to Workspace B while sess-1 is STILL running!
      await wsCtrl.select(wsB.id);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final afterWsSwitch = container.read(chatProvider);
      expect(afterWsSwitch.sessionId, isNull);
      expect(afterWsSwitch.isBusy, isFalse);
      expect(afterWsSwitch.backgroundRunningIds, contains('sess-1'));
      expect(afterWsSwitch.hasAnyRunningSession, isTrue);

      // 3. Start a concurrent turn in Workspace B (sess-2)
      final turnB = container.read(chatProvider.notifier).send('前台任务B');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(container.read(chatProvider).sessionId, 'sess-2');
      expect(container.read(chatProvider).runningSessionIds, containsAll(['sess-1', 'sess-2']));

      // 4. Stream updates into BACKGROUND sess-1 while sess-2 is visible!
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '后台工作区A顺利完成结果。'},
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 5. Cancel foreground sess-2 -> MUST NOT cancel background sess-1!
      await container.read(chatProvider.notifier).cancel();
      await turnB;
      expect(cancelledSessions, ['sess-2']);
      expect(container.read(chatProvider).backgroundRunningIds, contains('sess-1'));

      // 6. Complete background sess-1 with server usage tokens
      promptCompleters['sess-1']!.complete({
        'stopReason': 'end_turn',
        'usage': {'outputTokens': 120, 'thoughtTokens': 30},
      });
      await turnA;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(chatProvider).backgroundRunningIds, isEmpty);

      // 7. Re-open sess-1 from parked cache: zero session/load calls, full text + tok/s metrics intact!
      container.read(sessionsProvider.notifier).selectSession('sess-1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reopened = container.read(chatProvider);
      expect(loadCalls, 0);
      expect(reopened.sessionId, 'sess-1');
      final assistant = reopened.transcript.items.last as AssistantTranscriptItem;
      expect(assistant.text, '后台工作区A顺利完成结果。');
      expect(assistant.metrics, isNotNull);
      expect(assistant.metrics!.tokens, 150);
      expect(assistant.metrics!.tokensPerSecond, greaterThan(0));
    });

    testWidgets('ChatList renders chronological sub-thoughts, live edit diff preview, file changes card, and completed tok/s badge', (tester) async {
      final now = DateTime.now();
      var transcript = const ChatTranscript().appendUserPrompt('修改 main.dart');
      transcript = transcript.applyUpdate(
        const AgentThoughtChunkUpdate(AcpTextBlock('大思考：先读取 main.dart 确认入口')),
      );
      transcript = transcript.applyUpdate(
        const ToolCallCreatedUpdate(
          AcpToolCall(
            toolCallId: 'tc-read',
            title: '读取 lib/main.dart',
            kind: AcpToolKind.read,
            status: AcpToolStatus.completed,
          ),
        ),
      );
      transcript = transcript.applyUpdate(
        const AgentThoughtChunkUpdate(AcpTextBlock('小思考：找到旧标题，准备替换为新标题')),
      );
      transcript = transcript.applyUpdate(
        const ToolCallCreatedUpdate(
          AcpToolCall(
            toolCallId: 'tc-edit',
            name: 'replace_file_content',
            title: '编辑 lib/main.dart',
            kind: AcpToolKind.edit,
            status: AcpToolStatus.inProgress,
            rawInput: {
              'TargetFile': '/repo/lib/main.dart',
              'TargetContent': 'const title = "old";\n',
              'ReplacementContent': 'const title = "new";\nconst subtitle = "live";\n',
            },
          ),
        ),
      );

      final streamingState = ChatState(
        sessionId: 's-timeline',
        sessionCwd: '/repo',
        isSending: true,
        turnStartedAt: now.subtract(const Duration(seconds: 8)),
        lastActivityAt: now,
        livePhase: TurnLivePhase.working,
        liveTokensPerSecond: 44.8,
        transcript: transcript,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatProvider.overrideWith(() => _SeededChatController(streamingState)),
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

      // Primary thought + sub-thought appear chronologically!
      expect(find.text('思考'), findsOneWidget);
      expect(find.text('小思考'), findsOneWidget);
      // Real-time file changes summary card & live inline diff preview appear while editing!
      expect(find.text('正在修改文件 · 1 个'), findsOneWidget);
      expect(find.text('+2'), findsWidgets);
      expect(find.text('−1'), findsWidgets);

      // Now verify completed turn shows right-aligned tok/s badge in action bar!
      final finished = transcript
          .applyUpdate(const AgentMessageChunkUpdate(AcpTextBlock('已修改完成。')))
          .finishTurn(
            AcpStopReason.endTurn,
            metrics: const AcpTurnMetrics(
              tokensPerSecond: 54.2,
              tokens: 217,
              generationSeconds: 4.0,
              estimated: false,
            ),
          );
      final doneState = ChatState(
        sessionId: 's-timeline',
        sessionCwd: '/repo',
        transcript: finished,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('done'),
          overrides: [
            chatProvider.overrideWith(() => _SeededChatController(doneState)),
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

      expect(find.text('54.2 tok/s'), findsOneWidget);
      expect(find.text('文件变更 · 1 个文件'), findsOneWidget);
    });

    testWidgets('SessionsDrawer shows pulsing busy indicator for background-running sessions', (tester) async {
      final container = ProviderContainer(
        overrides: [
          chatProvider.overrideWith(
            () => _SeededChatController(
              const ChatState(
                sessionId: 'sess-fg',
                backgroundRunningIds: {'sess-bg'},
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final wsCtrl = container.read(workspacesProvider.notifier);
      await wsCtrl.add('/tmp/bg-ws', title: 'BG项目');
      final sessCtrl = container.read(sessionsProvider.notifier);
      sessCtrl.registerCreatedSession(
        AcpSessionInfo(
          sessionId: 'sess-bg',
          cwd: '/tmp/bg-ws',
          title: '后台运行中的任务',
          updatedAt: DateTime(2026, 11, 26, 12, 0),
        ),
        select: false,
      );
      sessCtrl.registerCreatedSession(
        AcpSessionInfo(
          sessionId: 'sess-fg',
          cwd: '/tmp/bg-ws',
          title: '当前浏览的空闲对话',
          updatedAt: DateTime(2026, 11, 26, 12, 5),
        ),
        select: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AgyGoApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: SessionsDrawer(
                  onClose: () {},
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('后台运行中的任务'), findsOneWidget);
      expect(find.text('当前浏览的空闲对话'), findsOneWidget);
      final busyDots = tester
          .widgetList<StatusDot>(find.byType(StatusDot))
          .where((d) => d.tone == StatusTone.busy)
          .toList();
      expect(busyDots.length, greaterThanOrEqualTo(1));
    });
  });
}

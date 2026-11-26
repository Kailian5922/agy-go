import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/runtime/runtime_channel.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/runtime_state.dart';
import 'package:agy_go/state/sessions_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/ui/chat/activity_strip.dart';
import 'package:agy_go/ui/chat/model_sheet.dart';
import 'package:agy_go/ui/chat/permission_controls.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubConnectionController extends ActiveConnectionController {
  _StubConnectionController(this._conn);

  final HostConnection _conn;

  @override
  Future<HostConnection?> build() async => _conn;
}

class _FakeRuntimeChannel extends RuntimeChannel {
  const _FakeRuntimeChannel();

  @override
  Future<Map<String, Object?>> fetchQuota() async => const {
    'exitCode': 0,
    'apiKeyMode': false,
    'stderr': '',
    'stdout':
        '{"status":"SUCCESS","command":{"name":"usage","data":{"groups":['
        '{"name":"Gemini Models","buckets":['
        '{"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.91},'
        '{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.84}'
        ']},'
        '{"name":"Claude and GPT models","buckets":['
        '{"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1.0},'
        '{"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.95}'
        ']}]}}}',
  };
}

class _FakeAgyAgent {
  _FakeAgyAgent() {
    final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
    client = AcpClient(clientTransport);
    agent = AcpJsonRpcPeer(agentTransport);
    _registerHandlers();
  }

  late final AcpClient client;
  late final AcpJsonRpcPeer agent;

  int newSessionCalls = 0;
  int loadSessionCalls = 0;
  int setConfigCalls = 0;
  final Map<String, List<String>> promptsBySession = {};
  final Map<String, String> modelBySession = {};
  final Map<String, String> thoughtBySession = {};

  List<Map<String, Object?>> _configOptionsFor(String sid) {
    final model = modelBySession[sid] ?? 'gemini-4-argon';
    final thought = thoughtBySession[sid] ?? 'medium';
    final supportsXhigh = model == 'gemini-4-hydrogen';
    final thoughts = [
      {'value': 'low', 'name': 'Low'},
      {'value': 'medium', 'name': 'Medium'},
      {'value': 'high', 'name': 'High'},
      if (supportsXhigh) {'value': 'xhigh', 'name': 'Extra High'},
    ];
    return [
      {
        'id': 'model',
        'name': 'Model',
        'type': 'select',
        'category': 'model',
        'currentValue': model,
        'options': [
          {
            'value': 'gemini-4-argon',
            'name': 'Gemini 4 Argon',
            'description': '日常开发均衡模型',
          },
          {
            'value': 'gemini-4-hydrogen',
            'name': 'Gemini 4 Hydrogen',
            'description': '深度推理与复杂工程',
          },
          {
            'value': 'claude-opus-5-5',
            'name': 'Claude Opus 5.5',
            'description': 'Anthropic 旗舰编程模型',
          },
        ],
      },
      {
        'id': 'thought_level',
        'name': 'Thought Level',
        'type': 'select',
        'category': 'thought_level',
        'currentValue': thoughts.any((t) => t['value'] == thought)
            ? thought
            : 'medium',
        'options': thoughts,
      },
      {
        'id': 'mode',
        'name': 'Mode',
        'type': 'select',
        'category': 'mode',
        'currentValue': 'default',
        'options': [
          {'value': 'default', 'name': 'Default', 'description': 'Ask before edits and commands'},
          {'value': 'accept-edits', 'name': 'Accept edits', 'description': 'Approve file edits'},
          {'value': 'plan', 'name': 'Plan', 'description': 'Plan carefully'},
        ],
      },
    ];
  }

  Map<String, Object?> _modesPayload() => {
    'currentModeId': 'default',
    'availableModes': [
      {'id': 'default', 'name': 'Default', 'description': 'Ask before edits and commands'},
      {'id': 'accept-edits', 'name': 'Accept edits', 'description': 'Approve file edits'},
      {'id': 'plan', 'name': 'Plan', 'description': 'Plan carefully'},
    ],
  };

  void _registerHandlers() {
    agent.onRequest('initialize', (params) async {
      return {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
        'agentCapabilities': {
          'loadSession': true,
          'promptCapabilities': {'image': true},
          'sessionCapabilities': {
            'list': {},
            'resume': {},
            'close': {},
            'delete': {},
          },
        },
      };
    });

    agent.onRequest('session/list', (params) async {
      return {'sessions': const <Object?>[]};
    });

    agent.onRequest('session/new', (params) async {
      newSessionCalls++;
      final sid = 'sess-$newSessionCalls';
      modelBySession[sid] = 'gemini-4-argon';
      thoughtBySession[sid] = 'medium';
      promptsBySession[sid] = [];
      return {
        'sessionId': sid,
        'modes': _modesPayload(),
        'configOptions': _configOptionsFor(sid),
      };
    });

    agent.onRequest('session/load', (params) async {
      loadSessionCalls++;
      final sid = params['sessionId']! as String;
      return {
        'sessionId': sid,
        'modes': _modesPayload(),
        'configOptions': _configOptionsFor(sid),
      };
    });

    agent.onRequest('session/close', (params) async => <String, Object?>{});

    agent.onRequest('session/set_config_option', (params) async {
      setConfigCalls++;
      final sid = params['sessionId']! as String;
      final configId = params['configId']! as String;
      final value = '${params['value']}';
      if (configId == 'model') {
        modelBySession[sid] = value;
      } else if (configId == 'thought_level') {
        thoughtBySession[sid] = value;
      }
      return {'configOptions': _configOptionsFor(sid)};
    });

    agent.onRequest('session/prompt', (params) async {
      final sid = params['sessionId']! as String;
      final promptBlocks = (params['prompt'] as List).whereType<Map>().toList();
      final text = promptBlocks
          .where((b) => b['type'] == 'text')
          .map((b) => '${b['text']}')
          .join('\n');
      promptsBySession.putIfAbsent(sid, () => []).add(text);

      await agent.sendNotification('session/update', {
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': '正在思考：$text'},
        },
      });
      await agent.sendNotification('session/update', {
        'sessionId': sid,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': '回复(${modelBySession[sid]}/${thoughtBySession[sid]}): $text',
          },
        },
      });
      return {'stopReason': 'end_turn'};
    });
  }

  Future<HostConnection> connect() async {
    final init = await client.initialize();
    return HostConnection(
      host: const HostRef.local(),
      label: '本机 Android',
      client: client,
      initResult: init,
      defaultCwd: '/storage/emulated/0/Download',
    );
  }

  Future<void> close() async {
    await client.close();
    await agent.close();
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'First turn in new workspace keeps reply & context and supports pre-chat model/effort selection',
    () async {
      final fake = _FakeAgyAgent();
      final conn = await fake.connect();
      addTearDown(fake.close);

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(
            () => _StubConnectionController(conn),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Subscribe so providers stay alive while async pre-warm completes.
      container.listen(activeConnectionProvider, (_, _) {});
      container.listen(chatProvider, (_, _) {});
      await container.read(activeConnectionProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // 1. Before sending any message, live models & thinking levels are ALREADY loaded!
      final preChat = container.read(chatProvider);
      expect(preChat.sessionId, isNull);
      expect(preChat.draftSessionId, 'sess-1');
      expect(preChat.modelConfigOption?.currentValue, 'gemini-4-argon');
      expect(
        preChat.thoughtLevelOption?.options.map((o) => o.value).toList(),
        ['low', 'medium', 'high'],
      );

      // 2. Select Gemini 4 Hydrogen BEFORE starting conversation -> xhigh unlocks dynamically!
      final switched = await container
          .read(chatProvider.notifier)
          .selectModel('gemini-4-hydrogen');
      expect(switched, isTrue);
      expect(
        container
            .read(chatProvider)
            .thoughtLevelOption
            ?.options
            .map((o) => o.value)
            .toList(),
        ['low', 'medium', 'high', 'xhigh'],
      );

      // 3. Pick xhigh thinking depth BEFORE message #1.
      final thoughtOk = await container
          .read(chatProvider.notifier)
          .selectThoughtLevel('xhigh');
      expect(thoughtOk, isTrue);
      expect(
        container.read(settingsProvider).preferredModelId,
        'gemini-4-hydrogen',
      );
      expect(container.read(settingsProvider).preferredThoughtLevel, 'xhigh');

      // 4. Send the VERY FIRST message in the new workspace!
      await container.read(chatProvider.notifier).send('你好，这是第一句话');

      // 5. Verify: NO spurious session/load, NO extra session/new, reply streamed & in context!
      expect(fake.loadSessionCalls, 0);
      expect(fake.newSessionCalls, 1);
      expect(fake.promptsBySession['sess-1'], ['你好，这是第一句话']);

      final afterFirst = container.read(chatProvider);
      expect(afterFirst.sessionId, 'sess-1');
      expect(afterFirst.draftSessionId, isNull);
      expect(container.read(sessionsProvider).currentSessionId, 'sess-1');
      expect(afterFirst.transcript.items.length, 2);
      expect(
        (afterFirst.transcript.items[0] as UserTranscriptItem).text,
        '你好，这是第一句话',
      );
      final reply1 = afterFirst.transcript.items[1] as AssistantTranscriptItem;
      expect(reply1.isStreaming, isFalse);
      expect(
        reply1.text,
        '回复(gemini-4-hydrogen/xhigh): 你好，这是第一句话',
      );

      // 6. Send second turn -> both turns stay in the SAME session context!
      await container.read(chatProvider.notifier).send('第二句话');
      expect(fake.promptsBySession['sess-1'], ['你好，这是第一句话', '第二句话']);
      expect(container.read(chatProvider).transcript.items.length, 4);
    },
  );

  testWidgets(
    'ModelModeChip shows live pre-chat model/effort and ModelSheet updates thinking levels without closing on model tap',
    (tester) async {
      final fake = _FakeAgyAgent();
      final conn = await fake.connect();
      addTearDown(fake.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _StubConnectionController(conn),
            ),
            runtimeChannelProvider.overrideWithValue(const _FakeRuntimeChannel()),
          ],
          child: const AgyGoApp(
            home: Scaffold(body: Center(child: ModelModeChip(grouped: false))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top-right chip immediately displays live model + Chinese thinking level BEFORE any chat!
      expect(find.textContaining('Gemini 4 Argon'), findsOneWidget);
      expect(find.textContaining('中'), findsOneWidget);

      // Tap chip -> opens card grid + capsule SegmentedPill (NOT a login screen!).
      await tester.tap(find.byType(ModelModeChip));
      await tester.pumpAndSettle();

      expect(find.text('选择模型'), findsOneWidget);
      // 「全部」 tab MUST NOT exist; only model family categories are shown.
      expect(find.text('全部'), findsNothing);
      expect(find.text('Gemini'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      // Defaults to the currently selected model's category (Gemini) & shows Gemini 5h/weekly quota.
      expect(find.text('Gemini 4 Hydrogen'), findsOneWidget);
      expect(find.text('Claude Opus 5.5'), findsNothing);
      expect(find.text('5 小时额度'), findsOneWidget);
      expect(find.text('周额度'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);
      expect(find.text('思考深度'), findsOneWidget);
      expect(find.text('超高'), findsNothing);

      // Switching to the Claude tab shows Claude models and switches quota to Claude / GPT.
      await tester.tap(find.text('Claude'));
      await tester.pumpAndSettle();
      expect(find.text('Claude Opus 5.5'), findsOneWidget);
      expect(find.text('Gemini 4 Hydrogen'), findsNothing);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);

      // Switch back to Gemini tab.
      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      expect(find.text('Gemini 4 Hydrogen'), findsOneWidget);

      // Duplicate raw ACP Mode / 会话模式 (Default / Accept edits / Plan) MUST NOT appear!
      expect(find.text('Mode'), findsNothing);
      expect(find.text('会话模式'), findsNothing);
      expect(find.text('Accept edits'), findsNothing);

      // Unified Antigravity official 4-tier permission hierarchy + /plan toggle MUST appear!
      expect(find.text('权限层级'), findsOneWidget);
      expect(find.text('询问确认'), findsOneWidget);
      expect(find.text('严格'), findsOneWidget);
      expect(find.text('沙箱'), findsOneWidget);
      expect(find.text('放行'), findsOneWidget);
      expect(find.text('计划模式（/plan）'), findsOneWidget);

      // Tap 「沙箱」 inside ModelSheet -> switches active permission to 「沙箱放行」 cleanly!
      await tester.ensureVisible(find.text('沙箱'));
      await tester.tap(find.text('沙箱'));
      await tester.pumpAndSettle();
      expect(find.text('沙箱放行'), findsOneWidget);

      // Tap Gemini 4 Hydrogen -> sheet stays open and dynamically reveals 「超高」!
      await tester.ensureVisible(find.text('Gemini 4 Hydrogen'));
      await tester.tap(find.text('Gemini 4 Hydrogen'));
      await tester.pumpAndSettle();

      expect(find.text('选择模型'), findsOneWidget);
      expect(find.text('超高'), findsOneWidget);

      // Tap 「超高」 -> applies xhigh and settles closed cleanly.
      await tester.ensureVisible(find.text('超高'));
      await tester.tap(find.text('超高'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gemini 4 Hydrogen'), findsOneWidget);
      expect(find.textContaining('超高'), findsOneWidget);
    },
  );

  test(
    'Reopening session via session/load clears streaming, cancel unlocks hung prompt immediately, and sendQueuedNow interrupts & sends',
    () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      final cancelEvents = <String>[];
      final receivedPrompts = <String>[];
      Completer<Map<String, Object?>>? hungPrompt;

      agent.onRequest('initialize', (_) async => {
            'protocolVersion': 1,
            'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
            'agentCapabilities': {
              'loadSession': true,
              'sessionCapabilities': {'list': {}, 'resume': {}},
            },
          });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async => {'sessionId': 'sess-draft'});
      agent.onRequest('session/close', (_) async => <String, Object?>{});
      agent.onNotification('session/cancel', (params) {
        cancelEvents.add('${params['sessionId']}');
      });

      agent.onRequest('session/load', (params) async {
        final sid = params['sessionId']! as String;
        // Replay 2 historical turns (simulating re-entering a session after network errors).
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'user_message_chunk',
            'content': {'type': 'text', 'text': '历史提问 1'},
          },
        });
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {
              'type': 'text',
              'text': 'There was a network issue connecting to the server.',
            },
          },
        });
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'user_message_chunk',
            'content': {'type': 'text', 'text': '历史提问 2'},
          },
        });
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {
              'type': 'text',
              'text': 'There was a network issue connecting to the server.',
            },
          },
        });
        return {'sessionId': sid};
      });

      agent.onRequest('session/prompt', (params) async {
        final sid = params['sessionId']! as String;
        final text = ((params['prompt'] as List).first as Map)['text'] as String;
        receivedPrompts.add(text);
        if (text == 'hung-turn') {
          await agent.sendNotification('session/update', {
            'sessionId': sid,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': '网络断开前部分输出'},
            },
          });
          hungPrompt = Completer<Map<String, Object?>>();
          return hungPrompt!.future;
        }
        await agent.sendNotification('session/update', {
          'sessionId': sid,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': '已立即回复: $text'},
          },
        });
        return {'stopReason': 'end_turn'};
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机 Android',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(
            () => _StubConnectionController(conn),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(activeConnectionProvider, (_, _) {});
      container.listen(chatProvider, (_, _) {});
      await container.read(activeConnectionProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // 1. Re-enter an existing session -> replayed turns MUST NOT stay streaming/busy!
      container.read(sessionsProvider.notifier).registerCreatedSession(
        const AcpSessionInfo(sessionId: 'sess-reopen', cwd: '/tmp/ws', title: 'Old'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final loaded = container.read(chatProvider);
      expect(loaded.sessionId, 'sess-reopen');
      expect(loaded.isLoadingSession, isFalse);
      expect(loaded.isBusy, isFalse);
      expect(loaded.transcript.isStreaming, isFalse);
      expect(loaded.transcript.items.length, 4);
      for (final a in loaded.transcript.items.whereType<AssistantTranscriptItem>()) {
        expect(a.isStreaming, isFalse);
      }

      // 2. Start a hung turn, queue a follow-up, then interrupt & send immediately via sendQueuedNow!
      final hungFuture = container.read(chatProvider.notifier).send('hung-turn');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(container.read(chatProvider).isBusy, isTrue);

      // Default queuedBehavior is queue: sending mid-turn enqueues it.
      await container.read(chatProvider.notifier).send('插队立即发');
      expect(container.read(chatProvider).queuedMessages, ['插队立即发']);

      // Tap 「立即发送」 on queued item #0 -> interrupts hung turn immediately without waiting!
      await container.read(chatProvider.notifier).sendQueuedNow(0);
      final afterImmediate = container.read(chatProvider);
      expect(afterImmediate.queuedMessages, isEmpty);
      expect(afterImmediate.isBusy, isFalse);
      expect(cancelEvents, contains('sess-reopen'));
      expect(receivedPrompts, ['hung-turn', '插队立即发']);
      expect(
        (afterImmediate.transcript.items.last as AssistantTranscriptItem).text,
        '已立即回复: 插队立即发',
      );

      // 3. Stray late chunks + late completion from the abandoned hung prompt must NOT re-stick UI!
      await agent.sendNotification('session/update', {
        'sessionId': 'sess-reopen',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '幽灵延迟分片'},
        },
      });
      hungPrompt!.complete({'stopReason': 'cancelled'});
      await hungFuture;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final finalState = container.read(chatProvider);
      expect(finalState.isBusy, isFalse);
      expect(finalState.transcript.isStreaming, isFalse);
      expect(
        (finalState.transcript.items.last as AssistantTranscriptItem).text,
        '已立即回复: 插队立即发',
      );
    },
  );

  testWidgets(
    'ModelModeChip(iconOnly: true) renders 44dp circular icon button without crushing title',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AgyGoApp(
            home: Scaffold(
              body: Center(child: ModelModeChip(grouped: false, iconOnly: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const ValueKey('chat-model-icon-btn'));
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn), const Size(44, 44));
    },
  );

  testWidgets(
    'Inline ActivityStrip and PermissionStatusPill sit side-by-side on one horizontal row without overflow',
    (tester) async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      final pendingPrompt = Completer<Map<String, Object?>>();

      agent.onRequest('initialize', (_) async => {
            'protocolVersion': 1,
            'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
            'agentCapabilities': {'loadSession': true},
          });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async => {'sessionId': 'sess-inline'});
      agent.onRequest('session/close', (_) async => <String, Object?>{});
      agent.onNotification('session/cancel', (_) {
        if (!pendingPrompt.isCompleted) {
          pendingPrompt.complete({'stopReason': 'cancelled'});
        }
      });
      agent.onRequest('session/prompt', (_) => pendingPrompt.future);

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机 Android',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(
            () => _StubConnectionController(conn),
          ),
        ],
      );
      addTearDown(() async {
        if (!pendingPrompt.isCompleted) {
          pendingPrompt.complete({'stopReason': 'cancelled'});
        }
        container.dispose();
        await client.close();
        await agent.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AgyGoApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: Row(
                  children: [
                    Expanded(child: ActivityStrip(inline: true)),
                    SizedBox(width: 8),
                    PermissionStatusPill(inline: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await container
            .read(chatProvider.notifier)
            .setSessionToolPermission(AgyToolPermission.alwaysProceed);
      });
      await tester.pump();
      expect(find.text('完全放行'), findsOneWidget);

      // Start an active turn so ActivityStrip(inline: true) renders beside PermissionStatusPill(inline: true).
      unawaited(container.read(chatProvider.notifier).send('测试并发胶囊'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('思考与生成中…'), findsOneWidget);
      expect(find.text('完全放行'), findsOneWidget);

      final actRect = tester.getRect(find.byType(ActivityStrip));
      final permRect = tester.getRect(find.byType(PermissionStatusPill));
      // Both capsules share the same horizontal row and Activity sits to the left of Permission.
      expect((actRect.center.dy - permRect.center.dy).abs(), lessThan(4));
      expect(actRect.right, lessThanOrEqualTo(permRect.left));

      // Cancel cleanly before teardown so ActivityStrip's periodic timer stops cleanly.
      await container.read(chatProvider.notifier).cancel();
      await tester.pump();
    },
  );
}

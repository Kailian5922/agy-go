import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/sessions_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/ui/chat/model_sheet.dart';
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
    ];
  }

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
        'configOptions': _configOptionsFor(sid),
      };
    });

    agent.onRequest('session/load', (params) async {
      loadSessionCalls++;
      final sid = params['sessionId']! as String;
      return {
        'sessionId': sid,
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
      expect(find.text('Gemini 4 Hydrogen'), findsOneWidget);
      expect(find.text('Claude Opus 5.5'), findsOneWidget);
      expect(find.text('思考深度'), findsOneWidget);
      expect(find.text('超高'), findsNothing);

      // Tap Gemini 4 Hydrogen -> sheet stays open and dynamically reveals 「超高」!
      await tester.tap(find.text('Gemini 4 Hydrogen'));
      await tester.pumpAndSettle();

      expect(find.text('选择模型'), findsOneWidget);
      expect(find.text('超高'), findsOneWidget);

      // Tap 「超高」 -> applies xhigh and settles closed cleanly.
      await tester.tap(find.text('超高'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gemini 4 Hydrogen'), findsOneWidget);
      expect(find.textContaining('超高'), findsOneWidget);
    },
  );
}

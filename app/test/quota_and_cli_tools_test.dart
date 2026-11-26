import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/agy_config_state.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/state/quota_state.dart';
import 'package:agy_go/ui/chat/diff_and_output_page.dart';
import 'package:agy_go/ui/chat/model_sheet.dart';
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

class _StubQuotaController extends QuotaController {
  _StubQuotaController(this._initial);
  final QuotaState _initial;

  @override
  QuotaState build() => _initial;

  @override
  Future<void> ensureLoaded({bool force = false}) async {}
}

class _StubAgyConfigController extends AgyConfigController {
  _StubAgyConfigController(this._state);
  final AgyConfigState _state;

  @override
  AgyConfigState build() => _state;
}

class _StubPhoneController extends PhoneControlController {
  _StubPhoneController(this._initial);
  final PhoneControlState _initial;

  @override
  PhoneControlState build() => _initial;

  void setTestState(PhoneControlState next) => state = next;
}

const _sampleAgyUsageJson = '''
{"conversation_id":"","status":"SUCCESS","response":"Gemini Models\\tWeekly Limit Remaining\\t96%\\t2026-11-14T02:40:30Z\\nGemini Models\\tFive Hour Limit Remaining\\t95%\\t2026-11-07T15:00:09Z\\nClaude and GPT models\\tWeekly Limit Remaining\\t92%\\t2026-11-14T11:01:57Z\\nClaude and GPT models\\tFive Hour Limit Remaining\\t88%\\t2026-11-07T16:01:57Z\\n","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit and a 5-hour limit.","groups":[{"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9619837,"reset_time":"2026-11-14T02:40:30Z"},{"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.9544959,"reset_time":"2026-11-07T15:00:09Z"}]},{"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[{"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.92,"reset_time":"2026-11-14T11:01:57Z"},{"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.88,"reset_time":"2026-11-07T16:01:57Z"}]}]}}}
''';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Quota parsing & formatting', () {
    test('parses structured agy -p /usage --output-format json with preamble logs', () {
      final res = parseAgyUsageCliOutput(
        'checking credentials...\n$_sampleAgyUsageJson',
      );
      expect(res.status, QuotaLoadStatus.loaded);
      expect(res.groups.length, 2);

      final gemini = res.groups[0];
      expect(gemini.displayName, 'Gemini 模型');
      expect(gemini.fiveHourBucket?.id, 'gemini-5h');
      expect(gemini.fiveHourBucket?.remainingFraction, closeTo(0.9545, 0.001));
      expect(gemini.weeklyBucket?.id, 'gemini-weekly');
      expect(gemini.weeklyBucket?.remainingFraction, closeTo(0.962, 0.001));
      expect(gemini.matchesCategory('Gemini'), isTrue);
      expect(gemini.matchesCategory('Claude'), isFalse);

      final thirdParty = res.groups[1];
      expect(thirdParty.displayName, 'Claude / GPT 模型');
      expect(thirdParty.fiveHourBucket?.remainingFraction, closeTo(0.88, 0.001));
      expect(thirdParty.weeklyBucket?.remainingFraction, closeTo(0.92, 0.001));
      expect(thirdParty.matchesCategory('Claude'), isTrue);
      expect(thirdParty.matchesCategory('OpenAI'), isTrue);
      expect(thirdParty.matchesCategory('Gemini'), isFalse);
    });

    test('parses weekly-only Starter/Free tier without inventing 5-hour bucket', () {
      const freeJson = '''
      {
        "status": "SUCCESS",
        "command": {
          "name": "usage",
          "data": {
            "groups": [
              {
                "name": "Gemini Models",
                "buckets": [
                  {"id": "gemini-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 0.75, "reset_time": "2026-12-01T00:00:00Z"}
                ]
              }
            ]
          }
        }
      }
      ''';
      final res = parseAgyUsageCliOutput(freeJson);
      expect(res.status, QuotaLoadStatus.loaded);
      expect(res.groups.single.fiveHourBucket, isNull);
      expect(res.groups.single.weeklyBucket?.remainingFraction, 0.75);
    });

    test('falls back to TSV response lines and detects signed-out state', () {
      const tsvOnly = '''
      {"status":"SUCCESS","response":"Gemini Models\\tFive Hour Limit Remaining\\t64%\\t2026-11-07T15:00:09Z\\nGemini Models\\tWeekly Limit Remaining\\t81%\\t2026-11-14T02:40:30Z"}
      ''';
      final parsed = parseAgyUsageCliOutput(tsvOnly);
      expect(parsed.status, QuotaLoadStatus.loaded);
      expect(parsed.groups.single.fiveHourBucket?.remainingFraction, closeTo(0.64, 0.001));
      expect(parsed.groups.single.weeklyBucket?.remainingFraction, closeTo(0.81, 0.001));

      final signedOut = parseAgyUsageCliOutput(
        '',
        stderr: 'Error: not logged in. Please sign in with agy.',
        exitCode: 1,
      );
      expect(signedOut.status, QuotaLoadStatus.notSignedIn);
    });

    test('formats quota percentages and reset countdowns cleanly', () {
      expect(formatQuotaPercent(0.954), '95%');
      expect(formatQuotaPercent(0.004), '<1%');
      expect(formatQuotaPercent(0.0), '0%');

      final now = DateTime.utc(2026, 11, 7, 11, 2, 0);
      expect(
        formatQuotaResetCountdown(DateTime.utc(2026, 11, 7, 15, 0, 0), now: now),
        '3小时58分后重置',
      );
      expect(
        formatQuotaResetCountdown(DateTime.utc(2026, 11, 14, 2, 2, 0), now: now),
        '6天15小时后重置',
      );
      expect(
        formatQuotaResetCountdown(DateTime.utc(2026, 11, 7, 11, 0, 0), now: now),
        '即将重置',
      );
    });
  });

  group('ModelSheet & UsageSheet 5h / weekly quota UI', () {
    testWidgets('ModelSheet has no 全部 tab and updates 5h & weekly quota per category', (tester) async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      agent.onRequest('initialize', (_) async => {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
        'agentCapabilities': {'loadSession': true},
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async => {
        'sessionId': 'sess-q',
        'configOptions': [
          {
            'id': 'model',
            'name': 'Model',
            'type': 'select',
            'category': 'model',
            'currentValue': 'gemini-4-argon',
            'options': [
              {'value': 'gemini-4-argon', 'name': 'Gemini 4 Argon'},
              {'value': 'gemini-4-neon', 'name': 'Gemini 4 Neon'},
              {'value': 'claude-opus-5-5', 'name': 'Claude Opus 5.5'},
              {'value': 'gpt-oss-120b', 'name': 'GPT-OSS 120B'},
            ],
          },
        ],
      });

      final init = await client.initialize();
      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机引擎',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final parsed = parseAgyUsageCliOutput(_sampleAgyUsageJson);
      final quotaState = QuotaState(
        status: QuotaLoadStatus.loaded,
        groups: parsed.groups,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
            quotaProvider.overrideWith(() => _StubQuotaController(quotaState)),
          ],
          child: const AgyGoApp(
            home: Scaffold(body: Center(child: ModelModeChip(grouped: false))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ModelModeChip));
      await tester.pumpAndSettle();

      // Category tabs only: NO 「全部」!
      expect(find.text('全部'), findsNothing);
      expect(find.text('Gemini'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('OpenAI'), findsOneWidget);

      // Default tab is Gemini -> displays Gemini 5h (95%) & weekly (96%) quota!
      expect(find.text('Gemini 模型 · 剩余额度'), findsOneWidget);
      expect(find.text('5 小时额度'), findsOneWidget);
      expect(find.text('周额度'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);

      // Tap Claude tab -> switches to Claude / GPT quota (88% / 92%)!
      await tester.tap(find.text('Claude'));
      await tester.pumpAndSettle();
      expect(find.text('Claude Opus 5.5'), findsOneWidget);
      expect(find.text('Claude / GPT 模型 · 剩余额度'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
    });

    testWidgets('ContextUsageSheet renders all groups 5h & weekly quotas', (tester) async {
      final parsed = parseAgyUsageCliOutput(_sampleAgyUsageJson);
      final quotaState = QuotaState(
        status: QuotaLoadStatus.loaded,
        groups: parsed.groups,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            quotaProvider.overrideWith(() => _StubQuotaController(quotaState)),
          ],
          child: AgyGoApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () => showContextUsageSheet(context, ref),
                  child: const Text('打开额度'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开额度'));
      await tester.pumpAndSettle();

      expect(find.text('订阅额度（5 小时 / 周额度）'), findsOneWidget);
      expect(find.text('Gemini 模型'), findsOneWidget);
      expect(find.text('Claude / GPT 模型'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
    });
  });

  group('CLI / ACP / MCP tool invocation contracts', () {
    test('AcpClient keeps client fs/terminal disabled and gates stdio/http/sse MCP properly + invalidates draft on MCP change', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      Map<String, Object?>? observedClientCaps;
      final sessionNewMcpPayloads = <List<Object?>>[];
      var seq = 0;

      agent.onRequest('initialize', (params) async {
        observedClientCaps = Map<String, Object?>.from(
          params['clientCapabilities']! as Map,
        );
        return {
          'protocolVersion': 1,
          'agentInfo': {'name': 'antigravity-cli', 'version': '1.5.17'},
          'agentCapabilities': {
            'loadSession': true,
            // HTTP supported, SSE NOT supported.
            'mcpCapabilities': {'http': true, 'sse': false},
          },
        };
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/close', (_) async => <String, Object?>{});
      agent.onRequest('session/new', (params) async {
        seq++;
        sessionNewMcpPayloads.add(List<Object?>.from(params['mcpServers']! as List));
        return {'sessionId': 'sess-$seq'};
      });
      agent.onRequest('session/prompt', (_) async => {'stopReason': 'end_turn'});

      final init = await client.initialize();
      // Client delegates NO fs/terminal RPCs so agy uses its own native tools reliably.
      final fsCaps = Map<String, Object?>.from(observedClientCaps!['fs']! as Map);
      expect(fsCaps['readTextFile'], isFalse);
      expect(fsCaps['writeTextFile'], isFalse);
      expect(observedClientCaps!['terminal'], isFalse);

      final conn = HostConnection(
        host: const HostRef.local(),
        label: '本机引擎',
        client: client,
        initResult: init,
        defaultCwd: '/tmp/ws',
      );

      final phoneCtrl = _StubPhoneController(const PhoneControlState(enabled: false));
      final container = ProviderContainer(
        overrides: [
          activeConnectionProvider.overrideWith(() => _StubConnection(conn)),
          phoneControlProvider.overrideWith(() => phoneCtrl),
          agyConfigProvider.overrideWith(
            () => _StubAgyConfigController(
              const AgyConfigState(
                loaded: true,
                mcpServers: [
                  AgyMcpServerEntry(
                    name: 'local-stdio',
                    transport: 'stdio',
                    command: '/system/bin/sh',
                    args: ['-c', 'echo ok'],
                  ),
                  AgyMcpServerEntry(
                    name: 'unsupported-sse',
                    transport: 'sse',
                    url: 'http://127.0.0.1:9999/sse',
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(activeConnectionProvider, (_, _) {});
      container.listen(chatProvider, (_, _) {});
      await container.read(activeConnectionProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Draft session #1 includes stdio MCP and filters out unsupported SSE MCP.
      expect(sessionNewMcpPayloads.length, 1);
      final names1 = sessionNewMcpPayloads.first
          .whereType<Map>()
          .map((m) => m['name'])
          .toList();
      expect(names1, ['local-stdio']);

      // Now user turns ON Phone Control MCP before sending message #1!
      phoneCtrl.setTestState(
        const PhoneControlState(
          enabled: true,
          mcpUrl: 'http://127.0.0.1:43210/mcp',
          mcpToken: 'tok-123',
        ),
      );

      // Sending message #1 MUST invalidate the stale draft session and create a fresh one with `phone` MCP!
      await container.read(chatProvider.notifier).send('测试工具调用');
      expect(sessionNewMcpPayloads.length, 2);
      final names2 = sessionNewMcpPayloads.last
          .whereType<Map>()
          .map((m) => m['name'])
          .toList();
      expect(names2, ['phone', 'local-stdio']);
    });
  });
}

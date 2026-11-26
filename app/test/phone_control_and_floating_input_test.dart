import 'dart:async';

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/agy_config_state.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/connection_state.dart';
import 'package:agy_go/state/pet_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/ui/pet/starling_pet.dart';
import 'package:agy_go/ui/phone/phone_control_screen.dart';
import 'package:agy_remote/agy_remote.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubConn extends ActiveConnectionController {
  _StubConn(this._conn);
  final HostConnection _conn;

  @override
  Future<HostConnection?> build() async => _conn;
}

class _SeededPhoneController extends PhoneControlController {
  _SeededPhoneController(this._initial);
  final PhoneControlState _initial;

  @override
  PhoneControlState build() => _initial;
}

class _SeededPetController extends PetController {
  _SeededPetController(this._initial);
  final PetSettingsState _initial;

  @override
  PetSettingsState build() => _initial;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Official Antigravity MCP config serialization', () {
    test('AgyMcpServerEntry serializes HTTP servers with serverUrl and parses legacy url/httpUrl', () {
      const entry = AgyMcpServerEntry(
        name: 'docs',
        transport: 'http',
        url: 'http://127.0.0.1:41234/mcp',
        headers: {'Authorization': 'Bearer secret'},
      );
      final json = entry.toJson();
      expect(json['serverUrl'], 'http://127.0.0.1:41234/mcp');
      expect(json.containsKey('httpUrl'), isFalse);

      final fromServerUrl = AgyMcpServerEntry.fromJson('docs', json);
      expect(fromServerUrl.url, 'http://127.0.0.1:41234/mcp');
      expect(fromServerUrl.transport, 'http');

      final fromLegacy = AgyMcpServerEntry.fromJson('legacy', {
        'httpUrl': 'http://127.0.0.1:42000/mcp',
      });
      expect(fromLegacy.url, 'http://127.0.0.1:42000/mcp');
      expect(fromLegacy.transport, 'http');
    });
  });

  group('Out-of-app floating ask bar Dart bridge (DSH Go scheme)', () {
    test('askTarget, askSend (current & fresh without interrupting background turn), askStop, and prefill work end-to-end', () async {
      final (clientTransport, agentTransport) = MemoryAcpTransport.pair();
      final client = AcpClient(clientTransport);
      final agent = AcpJsonRpcPeer(agentTransport);
      addTearDown(() async {
        await client.close();
        await agent.close();
      });

      var nextSid = 0;
      final promptCompleters = <String, Completer<Map<String, Object?>>>{};
      final receivedPrompts = <(String, String)>[];

      agent.onRequest('initialize', (_) async => {
        'protocolVersion': 1,
        'agentInfo': {'name': 'antigravity-cli', 'version': '1.6.0'},
        'agentCapabilities': {'loadSession': true},
      });
      agent.onRequest('session/list', (_) async => {'sessions': const <Object?>[]});
      agent.onRequest('session/new', (_) async {
        nextSid++;
        return {'sessionId': 'float-sess-$nextSid'};
      });
      agent.onRequest('session/prompt', (params) async {
        final sid = params['sessionId']! as String;
        final text = ((params['prompt'] as List).first as Map)['text'] as String;
        receivedPrompts.add((sid, text));
        final c = Completer<Map<String, Object?>>();
        promptCompleters[sid] = c;
        return c.future;
      });
      agent.onNotification('session/cancel', (params) {
        final sid = params['sessionId'] as String?;
        final c = sid != null ? promptCompleters[sid] : null;
        if (c != null && !c.isCompleted) {
          c.complete({'stopReason': 'cancelled'});
        }
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
          activeConnectionProvider.overrideWith(() => _StubConn(conn)),
        ],
      );
      addTearDown(container.dispose);

      container.read(chatProvider);
      final petCtrl = container.read(petSettingsProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // 1. Floating ask bar queries target before any session exists -> offers fresh chat.
      final target1 = await petCtrl.handleNativeCallForTest(
        const MethodCall('askTarget', {'fresh': false}),
      ) as Map<Object?, Object?>;
      expect(target1['problem'], isNull);
      expect(target1['fresh'], isA<Map>());

      // 2. Send first question from outside the app via askSend!
      final send1 = await petCtrl.handleNativeCallForTest(
        const MethodCall('askSend', {'text': '应用外悬浮提问1', 'fresh': false}),
      ) as Map<Object?, Object?>;
      expect(send1['sent'], isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedPrompts.length, 1);
      final firstSid = receivedPrompts.first.$1;
      expect(receivedPrompts.first.$2, '应用外悬浮提问1');
      expect(container.read(chatProvider).isBusy, isTrue);

      // 3. While turn 1 is STILL running, send a second question with fresh=true from floating bar:
      //    must park turn 1 in background (not cancel it!) and start a concurrent new chat!
      final send2 = await petCtrl.handleNativeCallForTest(
        const MethodCall('askSend', {'text': '新对话并发提问2', 'fresh': true}),
      ) as Map<Object?, Object?>;
      expect(send2['sent'], isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedPrompts.length, 2);
      expect(receivedPrompts[1].$2, '新对话并发提问2');
      expect(container.read(chatProvider).backgroundRunningIds, contains(firstSid));

      // 4. askStop cancels only the foreground session, leaving background turn 1 alive.
      await petCtrl.handleNativeCallForTest(const MethodCall('askStop'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(chatProvider).backgroundRunningIds, contains(firstSid));

      // Clean up background completer.
      promptCompleters[firstSid]!.complete({'stopReason': 'end_turn'});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(chatProvider).backgroundRunningIds, isEmpty);

      // 5. Fallback prefill text from native intent populates pendingPrefillText.
      await petCtrl.handleNativeCallForTest(
        const MethodCall('prefillComposer', {'text': '冷启动草稿'}),
      );
      expect(container.read(petSettingsProvider).pendingPrefillText, '冷启动草稿');
      petCtrl.clearPendingPrefill();
      expect(container.read(petSettingsProvider).pendingPrefillText, isNull);
    });
  });

  group('PhoneControlScreen & PetSettingsPage diagnostics and floating input UI', () {
    testWidgets('PhoneControlScreen surfaces restricted settings guidance, self-check details, and floating input switch', (tester) async {
      const phoneState = PhoneControlState(
        enabled: true,
        accessibilityConnected: false,
        restrictedSettings: 'guarded',
        mcpUrl: 'http://127.0.0.1:45678/mcp',
        mcpToken: 'tok',
        lastSelfCheck: PhoneSelfCheckReport(
          ok: false,
          mcpProbeOk: true,
          mcpProbeDetail: '本地 MCP 环回通信正常（8 个工具就绪，127.0.0.1:45678）',
          mcpConfigOk: true,
          mcpClientConnected: false,
          accessibilityConnected: false,
          accessibilityEnabledInSettings: false,
          screenReadOk: false,
          summary: '无障碍未开启：Android 侧载应用需先在「应用信息 › ⋮」允许受限设置',
          restrictedSettings: 'guarded',
        ),
      );
      const petState = PetSettingsState(
        showSystemOverlay: false,
        canUseAccessibilityOverlay: false,
        canDrawOverlays: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            phoneControlProvider.overrideWith(() => _SeededPhoneController(phoneState)),
            petSettingsProvider.overrideWith(() => _SeededPetController(petState)),
          ],
          child: const AgyGoApp(home: PhoneControlScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('需先解除「受限设置」再开无障碍'), findsOneWidget);
      expect(find.text('打开应用信息（解除受限设置）'), findsOneWidget);

      final listFinder = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('一键自检手机操控连接'),
        200,
        scrollable: listFinder,
      );
      expect(find.text('一键自检手机操控连接'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('自检结果明细'),
        200,
        scrollable: listFinder,
      );
      expect(find.text('自检结果明细'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('~/.gemini/config/mcp_config.json 已同步 serverUrl'),
        200,
        scrollable: listFinder,
      );
      expect(
        find.text('~/.gemini/config/mcp_config.json 已同步 serverUrl'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('启用应用外悬浮输入球'),
        200,
        scrollable: listFinder,
      );
      expect(find.text('启用应用外悬浮输入球'), findsOneWidget);
    });

    testWidgets('PetSettingsPage shows DSH Go floating input controls and accessibility-overlay readiness', (tester) async {
      const petState = PetSettingsState(
        showInApp: true,
        showSystemOverlay: true,
        onlyOutsideApp: true,
        canDrawOverlays: false,
        canUseAccessibilityOverlay: true,
        permissionMode: 'accessibility',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            petSettingsProvider.overrideWith(() => _SeededPetController(petState)),
          ],
          child: const AgyGoApp(home: PetSettingsPage()),
        ),
      );
      await tester.pump();

      expect(find.text('应用外悬浮输入（DSH Go 同款方案）'), findsOneWidget);
      expect(find.text('应用外桌面悬浮球与悬浮输入'), findsOneWidget);
      expect(find.text('已通过无障碍悬浮就绪（免额外悬浮窗权限）'), findsOneWidget);
      expect(find.text('仅在切出 AGY Go 后显示'), findsOneWidget);
      expect(find.text('立即弹出悬浮输入条体验'), findsOneWidget);
    });
  });
}

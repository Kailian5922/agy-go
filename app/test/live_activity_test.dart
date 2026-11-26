import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/live_activity_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/ui/settings/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLiveChannel extends LiveActivityChannel {
  _FakeLiveChannel(this._status);

  final LiveActivitySystemStatus _status;
  final List<LiveActivityPush> pushes = [];
  bool openedSettings = false;

  @override
  Future<void> push(LiveActivityPush data) async {
    pushes.add(data);
  }

  @override
  Future<LiveActivitySystemStatus> status() async => _status;

  @override
  Future<bool> openLiveSettings() async {
    openedSettings = true;
    return true;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('deriveLiveActivity reducer', () {
    const idlePhone = PhoneControlState();
    const settings = AppSettings();

    test('returns null when idle in foreground', () {
      final res = deriveLiveActivity(
        chat: const ChatState(),
        phone: idlePhone,
        sessionTitle: '测试对话',
        settings: settings,
        foreground: true,
      );
      expect(res, isNull);
    });

    test('derives running capsule with cleaned tool path and timer', () {
      final started = DateTime(2026, 11, 26, 10, 0, 0);
      final transcript = ChatTranscript(
        items: [
          AssistantTranscriptItem(
            id: 'a1',
            timestamp: started,
            isStreaming: true,
            toolCalls: const [
              AcpToolCall(
                toolCallId: 'tc1',
                title:
                    'File ../../../../../../storage/emulated/0/game/冬日狂想曲/www/js/plugins.js',
                kind: AcpToolKind.read,
                status: AcpToolStatus.inProgress,
              ),
            ],
          ),
        ],
      );
      final chat = ChatState(
        sessionId: 's1',
        sessionCwd: '/storage/emulated/0/game/冬日狂想曲',
        transcript: transcript,
        isSending: true,
        turnStartedAt: started,
      );

      final res = deriveLiveActivity(
        chat: chat,
        phone: idlePhone,
        sessionTitle: '添加汉化',
        settings: settings,
        foreground: false,
      );

      expect(res, isNotNull);
      expect(res!.kind, LiveActivityKind.running);
      expect(res.title, '添加汉化');
      expect(res.chip, '干活中');
      expect(res.text, '读取 · www/js/plugins.js');
      expect(res.text.contains('../'), isFalse);
      expect(res.sinceMs, started.millisecondsSinceEpoch);
    });

    test('prioritizes waiting approval and phone approval over running', () {
      const phoneWaiting = PhoneControlState(
        pendingApprovals: [
          PhoneApprovalPrompt(
            id: 'pa1',
            tool: 'tap',
            summary: '点击微信发送按钮',
            reason: '需要用户确认点击操作',
            riskLevel: 'sensitive',
          ),
        ],
      );
      final res = deriveLiveActivity(
        chat: const ChatState(isSending: true),
        phone: phoneWaiting,
        sessionTitle: '测试',
        settings: settings,
        foreground: false,
      );

      expect(res, isNotNull);
      expect(res!.kind, LiveActivityKind.waiting);
      expect(res.chip, '待确认');
      expect(res.title, '手机操控等待确认');
      expect(res.text, '点击微信发送按钮');
    });

    test('shows brief done / failed receipt only when backgrounded', () {
      final doneBg = deriveLiveActivity(
        chat: const ChatState(),
        phone: idlePhone,
        sessionTitle: '添加汉化',
        settings: settings,
        foreground: false,
        ending: LiveEndingKind.done,
      );
      expect(doneBg?.kind, LiveActivityKind.done);
      expect(doneBg?.chip, '完成');

      final doneFg = deriveLiveActivity(
        chat: const ChatState(),
        phone: idlePhone,
        sessionTitle: '添加汉化',
        settings: settings,
        foreground: true,
        ending: LiveEndingKind.done,
      );
      expect(doneFg, isNull);
    });
  });

  testWidgets(
    'NotificationSettingsPage shows Live Activity toggle and blocked permission banner',
    (tester) async {
      final fake = _FakeLiveChannel(
        const LiveActivitySystemStatus(
          supported: true,
          allowed: false,
          settingsAvailable: true,
          sdk: 36,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveActivityChannelProvider.overrideWithValue(fake),
          ],
          child: const AgyGoApp(home: NotificationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('通知与胶囊提醒'), findsWidgets);
      expect(find.text('实时活动（胶囊通知）'), findsOneWidget);
      expect(find.text('显示实时活动'), findsOneWidget);
      expect(find.text('系统没有允许实时活动'), findsOneWidget);
      expect(find.text('待系统开启'), findsOneWidget);

      await tester.tap(find.text('前往开启'));
      await tester.pumpAndSettle();
      expect(fake.openedSettings, isTrue);
    },
  );
}

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
      expect(res.chip, '执行中');
      expect(res.text, 'www/js/plugins.js');
      expect(res.text.contains('../'), isFalse);
      expect(res.sinceMs, started.millisecondsSinceEpoch);

      // Native rawInput.toolAction is surfaced verbatim on Live Activity capsule.
      final editChat = ChatState(
        sessionId: 's1',
        sessionCwd: '/storage/emulated/0/game/冬日狂想曲',
        transcript: ChatTranscript(
          items: [
            AssistantTranscriptItem(
              id: 'a2',
              timestamp: started,
              isStreaming: true,
              toolCalls: const [
                AcpToolCall(
                  toolCallId: 'tc2',
                  name: 'edit_file',
                  title: 'edit_file',
                  kind: AcpToolKind.edit,
                  status: AcpToolStatus.inProgress,
                  rawInput: {
                    'Path': '/storage/emulated/0/game/冬日狂想曲/www/js/plugins.js',
                    'toolAction': 'Editing plugins.js',
                    'toolSummary': 'Edit plugins.js',
                  },
                ),
              ],
            ),
          ],
        ),
        isSending: true,
        turnStartedAt: started,
      );
      final editRes = deriveLiveActivity(
        chat: editChat,
        phone: idlePhone,
        sessionTitle: '添加汉化',
        settings: settings,
        foreground: false,
      );
      expect(editRes?.chip, '执行中');
      expect(editRes?.text, 'Editing plugins.js');

      // Background parked running conversation keeps Live Activity alive
      final bgRes = deriveLiveActivity(
        chat: const ChatState(
          sessionId: 's2',
          backgroundRunningIds: {'s1'},
        ),
        phone: idlePhone,
        sessionTitle: '空闲会话',
        settings: settings,
        foreground: false,
      );
      expect(bgRes?.kind, LiveActivityKind.running);
      expect(bgRes?.chip, '后台运行');
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

    test('surfaces parked background approval, single background running tool, and stopping state', () {
      final started = DateTime(2026, 11, 27, 8, 0, 0);

      // Parked background session blocked on permission approval outranks foreground busy turn.
      final bgApproval = deriveLiveActivity(
        chat: ChatState(
          sessionId: 'fg-1',
          isSending: true,
          backgroundRunningIds: const {'bg-1'},
          backgroundSummaries: {
            'bg-1': BackgroundSessionSummary(
              sessionId: 'bg-1',
              title: '重构任务',
              isBusy: true,
              hasPendingPermission: true,
              pendingPermissionLabel: '运行 git push',
              turnStartedAt: started,
            ),
          },
        ),
        phone: idlePhone,
        sessionTitle: '前台对话',
        settings: settings,
        foreground: false,
      );
      expect(bgApproval, isNotNull);
      expect(bgApproval!.kind, LiveActivityKind.waiting);
      expect(bgApproval.chip, '待确认');
      expect(bgApproval.title, '重构任务');
      expect(bgApproval.text, '等待确认 · 运行 git push');
      expect(bgApproval.sessionId, 'bg-1');
      expect(bgApproval.sinceMs, started.millisecondsSinceEpoch);

      // Single running background session surfaces real title, concurrent tools, and chronometer.
      final bgRunning = deriveLiveActivity(
        chat: ChatState(
          sessionId: 'fg-idle',
          backgroundRunningIds: const {'bg-2'},
          backgroundSummaries: {
            'bg-2': BackgroundSessionSummary(
              sessionId: 'bg-2',
              title: '单测修复',
              isBusy: true,
              livePhase: TurnLivePhase.working,
              activeToolLabel: 'Editing chat_state.dart',
              activeToolCount: 2,
              turnStartedAt: started,
            ),
          },
        ),
        phone: idlePhone,
        sessionTitle: '空闲对话',
        settings: settings,
        foreground: false,
      );
      expect(bgRunning, isNotNull);
      expect(bgRunning!.kind, LiveActivityKind.running);
      expect(bgRunning.chip, '后台运行');
      expect(bgRunning.title, '单测修复');
      expect(bgRunning.text, 'Editing chat_state.dart (+1)');
      expect(bgRunning.sessionId, 'bg-2');
      expect(bgRunning.sinceMs, started.millisecondsSinceEpoch);

      // Foreground stopping turn shows honest 停止中 chip.
      final stopping = deriveLiveActivity(
        chat: ChatState(
          sessionId: 'fg-stop',
          isSending: true,
          isStopping: true,
          turnStartedAt: started,
        ),
        phone: idlePhone,
        sessionTitle: '测试对话',
        settings: settings,
        foreground: false,
      );
      expect(stopping?.chip, '停止中');
      expect(stopping?.text, '正在中止当前轮次…');
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

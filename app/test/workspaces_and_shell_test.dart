import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/sessions_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/state/workspaces_state.dart';
import 'package:agy_go/ui/chat/empty_state.dart';
import 'package:agy_go/ui/features/all_features_page.dart';
import 'package:agy_go/ui/settings/settings_screen.dart';
import 'package:agy_go/ui/shell/sessions_drawer.dart';
import 'package:agy_go/ui/system/keep_alive_screen.dart';
import 'package:agy_go/ui/theme/theme.dart';
import 'package:agy_go/ui/workspace/workspaces_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Workspace path display & multi-workspace registry', () {
    test('displayWorkspacePath shortens phone storage and home paths', () {
      expect(
        displayWorkspacePath('/storage/emulated/0', local: true),
        '手机存储',
      );
      expect(
        displayWorkspacePath(
          '/storage/emulated/0/Download/AGY-Go',
          local: true,
        ),
        '手机存储/Download/AGY-Go',
      );
      expect(
        displayWorkspacePath(
          '/data/user/0/app/home/workspace',
          local: true,
          homePath: '/data/user/0/app/home',
        ),
        '~/workspace',
      );
      expect(
        displayWorkspacePath('/srv/repo', local: false),
        '/srv/repo',
      );
    });

    test('WorkspacesController adds, selects, pins, groups, and removes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctrl = container.read(workspacesProvider.notifier);
      final dl = await ctrl.add('/storage/emulated/0/Download');
      expect(dl.displayTitle, '下载');
      final storage = await ctrl.add('/storage/emulated/0');
      expect(storage.displayTitle, '手机存储');

      final added = await ctrl.add('/storage/emulated/0/Documents/notes');
      expect(added.displayTitle, 'notes');
      expect(container.read(workspacesProvider).selected?.id, added.id);

      await ctrl.setPinned(added.id, true);
      expect(
        container.read(workspacesProvider).sections.first.kind,
        WorkspaceSectionKind.pinned,
      );

      await ctrl.setPinned(added.id, false);
      await ctrl.setGroup(added.id, '工作');
      expect(container.read(workspacesProvider).groupNames, contains('工作'));

      await ctrl.remove(added.id);
      expect(
        container.read(workspacesProvider).workspaces.any((w) => w.id == added.id),
        isFalse,
      );
    });

    test('SettingsController hides status bar by default and persists toggle', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(settingsProvider).hideStatusBar, isTrue);
      await container.read(settingsProvider.notifier).setHideStatusBar(false);
      expect(container.read(settingsProvider).hideStatusBar, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('agy.hideStatusBar'), isFalse);
    });

    test('AppAccentId migrates legacy accent names safely', () {
      expect(AppAccentId.parse('nebula'), AppAccentId.mist);
      expect(AppAccentId.parse('aurora'), AppAccentId.daiqing);
      expect(AppAccentId.parse('emerald'), AppAccentId.turquoise);
      expect(AppAccentId.parse('graphite'), AppAccentId.graphite);
    });
  });

  group('DSH Go UI surfaces render cleanly', () {
    testWidgets('WorkspacesPage renders phone storage and Download quick mounts', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: WorkspacesPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('工作区'), findsWidgets);
      expect(find.text('手机存储与快捷挂载'), findsOneWidget);
      expect(find.text('允许 agy 访问手机存储'), findsOneWidget);
      expect(find.text('手机存储'), findsOneWidget);
      expect(find.text('下载 (Download)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('图片 (Pictures)'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('文档 (Documents)'), findsOneWidget);
      expect(find.text('相册 (DCIM)'), findsOneWidget);
      expect(find.text('图片 (Pictures)'), findsOneWidget);
    });

    testWidgets('SettingsScreen renders hub overview and storage entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: SettingsScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsWidgets);
      expect(find.text('权限层级'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('手机存储挂载'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('手机存储挂载'), findsOneWidget);
      expect(find.text('工作区管理'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('外观、配色与壁纸'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('外观、配色与壁纸'), findsOneWidget);
    });

    testWidgets('AllFeaturesPage renders 2-column feature tiles', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: AllFeaturesPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部功能'), findsWidgets);
      expect(find.text('审批与执行模式'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('工作区管理'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('工作区管理'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('手机存储挂载'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('手机存储挂载'), findsOneWidget);
      expect(find.text('星灵桌宠'), findsOneWidget);
    });

    testWidgets('ChatEmptyState renders workspace chip & 2x2 suggestion cards', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(accent: AppAccent.mist, glassBlur: false),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatEmptyState(
                connected: true,
                workspace: '手机存储',
                onWorkspace: () {},
                now: DateTime(2026, 11, 25, 15, 0),
                tipStart: 0,
                onSuggestion: (s) => picked = s.label,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('下午好'), findsOneWidget);
      expect(find.text('在「手机存储」中'), findsOneWidget);
      expect(find.text('看看工作区'), findsOneWidget);
      await tester.tap(find.text('看看工作区'));
      expect(picked, '看看工作区');
    });

    test(
      'workspaceSessionGroupsProvider groups sessions under longest-prefix workspaces and persists collapse state',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final wsCtrl = container.read(workspacesProvider.notifier);
        final storageWs = await wsCtrl.add('/storage/emulated/0', title: '手机存储');
        final projWs = await wsCtrl.add(
          '/storage/emulated/0/Download/my-app',
          title: 'my-app',
        );

        final sessCtrl = container.read(sessionsProvider.notifier);
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_sub',
            cwd: '/sdcard/Download/my-app/lib',
            title: '子目录会话',
            updatedAt: DateTime(2026, 11, 25, 12, 0),
          ),
        );
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_storage',
            cwd: '/storage/emulated/0/DCIM',
            title: '相册整理',
            updatedAt: DateTime(2026, 11, 25, 11, 0),
          ),
        );
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_extra',
            cwd: '/tmp/unregistered-repo',
            title: '临时仓库会话',
            updatedAt: DateTime(2026, 11, 25, 10, 0),
          ),
        );

        final groups = container.read(workspaceSessionGroupsProvider);
        final projGroup = groups.singleWhere((g) => g.key == projWs.id);
        final storageGroup = groups.singleWhere((g) => g.key == storageWs.id);
        final extraGroup = groups.singleWhere(
          (g) => g.key == 'path:/tmp/unregistered-repo',
        );

        // /sdcard/Download/my-app/lib canonicalizes to /storage/emulated/0/... and matches longest prefix `my-app`!
        expect(projGroup.sessions.map((s) => s.sessionId), ['s_sub']);
        expect(storageGroup.sessions.map((s) => s.sessionId), ['s_storage']);
        expect(extraGroup.title, 'unregistered-repo');
        expect(extraGroup.sessions.map((s) => s.sessionId), ['s_extra']);

        // Workspace collapse state toggles and persists cleanly.
        await sessCtrl.toggleWorkspaceCollapsed(projWs.id);
        expect(
          container.read(sessionsProvider).isWorkspaceCollapsed(projWs.id),
          isTrue,
        );
        await sessCtrl.toggleWorkspaceCollapsed(projWs.id);
        expect(
          container.read(sessionsProvider).isWorkspaceCollapsed(projWs.id),
          isFalse,
        );
      },
    );

    testWidgets(
      'SessionsDrawer displays workspaces with nested conversations underneath and toggles collapse on tap',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final wsCtrl = container.read(workspacesProvider.notifier);
        await wsCtrl.add('/tmp/project-alpha', title: 'Alpha 项目');

        final sessCtrl = container.read(sessionsProvider.notifier);
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_alpha_1',
            cwd: '/tmp/project-alpha',
            title: 'Alpha 的第一个对话',
            updatedAt: DateTime(2026, 11, 25, 12, 0),
          ),
        );
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_alpha_2',
            cwd: '/tmp/project-alpha',
            title: 'Alpha 的第二个对话',
            updatedAt: DateTime(2026, 11, 25, 11, 0),
          ),
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: AgyGoApp(
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: SessionsDrawer(onClose: () {}, onOpen: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Alpha 项目'), findsWidgets);
        expect(find.text('Alpha 的第一个对话'), findsOneWidget);
        expect(find.text('Alpha 的第二个对话'), findsOneWidget);

        // Tap the Alpha workspace header -> collapses its nested conversations!
        final wsHeader = find.descendant(
          of: find.byKey(
            ValueKey(
              'ws-group-${container.read(workspacesProvider).workspaces.last.id}',
            ),
          ),
          matching: find.text('Alpha 项目'),
        );
        await tester.tap(wsHeader);
        await tester.pumpAndSettle();

        expect(find.text('Alpha 的第一个对话'), findsNothing);
      },
    );

    testWidgets(
      'keepScreenOnWhileRunning persists, renders in SettingsScreen & KeepAliveScreen, and dispatches native channel',
      (tester) async {
        final keepScreenCalls = <bool>[];
        const channel = MethodChannel('agy/system');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'setKeepScreenOn') {
                keepScreenCalls.add((call.arguments as Map)['enabled'] == true);
                return true;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(settingsProvider).keepScreenOnWhileRunning, isTrue);
        await container
            .read(settingsProvider.notifier)
            .setKeepScreenOnWhileRunning(false);
        expect(
          container.read(settingsProvider).keepScreenOnWhileRunning,
          isFalse,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('agy.keepScreenOnWhileRunning'), isFalse);

        // Verify visible in SettingsScreen and KeepAliveScreen.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const AgyGoApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('模型运行时保持屏幕常亮'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('模型运行时保持屏幕常亮'), findsOneWidget);

        // Idle app sends keepScreenOn=false on boot.
        expect(keepScreenCalls, contains(false));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const AgyGoApp(home: KeepAliveScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('模型运行时保持屏幕常亮'), findsOneWidget);
      },
    );
  });
}

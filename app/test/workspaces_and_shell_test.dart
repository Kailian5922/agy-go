import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/drawer_view_state.dart';
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
      expect(dl.displayTitle, 'Download');
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
    testWidgets('WorkspacesPage renders only 手机存储 quick mount without media/download shortcuts', (
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
      expect(find.text('下载 (Download)'), findsNothing);
      expect(find.text('文档 (Documents)'), findsNothing);
      expect(find.text('相册 (DCIM)'), findsNothing);
      expect(find.text('图片 (Pictures)'), findsNothing);
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
      'drawerScopeProvider and workspaceCountsProvider match longest-prefix workspaces cleanly',
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

        // /sdcard/Download/my-app/lib canonicalizes to /storage/emulated/0/... and matches longest prefix `my-app`!
        final counts = container.read(workspaceCountsProvider);
        expect(counts[projWs.id], 1);
        expect(counts[storageWs.id], 1);
        expect(container.read(visibleSessionTotalProvider), 3);

        // Scoped to my-app -> only s_sub.
        await wsCtrl.select(projWs.id);
        expect(
          container.read(drawerScopeProvider).sessions.map((s) => s.sessionId),
          ['s_sub'],
        );

        // Scoped to 全部对话 (null) -> all 3 visible sessions!
        await wsCtrl.select(null);
        expect(
          container.read(drawerScopeProvider).sessions.map((s) => s.sessionId),
          containsAll(['s_sub', 's_storage', 's_extra']),
        );
      },
    );

    testWidgets(
      'SessionsDrawer mirrors DSH Go layout: workspace scope switcher, status filters, pinned/folder/day blocks, folder collapse, and multi-select',
      (tester) async {
        final fixedNow = DateTime(2026, 11, 26, 15, 0);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final wsCtrl = container.read(workspacesProvider.notifier);
        await wsCtrl.add('/tmp/project-alpha', title: 'Alpha 项目');
        await wsCtrl.add('/tmp/project-beta', title: 'Beta 项目');
        // Select Alpha 项目 as the active scope.
        final alphaWs = container
            .read(workspacesProvider)
            .workspaces
            .firstWhere((w) => w.title == 'Alpha 项目');
        await wsCtrl.select(alphaWs.id);

        final sessCtrl = container.read(sessionsProvider.notifier);
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_pinned',
            cwd: '/tmp/project-alpha',
            title: '置顶对话',
            updatedAt: DateTime(2026, 11, 26, 14, 0),
          ),
        );
        await sessCtrl.togglePin('s_pinned');
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_folder',
            cwd: '/tmp/project-alpha',
            title: '文件夹里的对话',
            updatedAt: DateTime(2026, 11, 26, 13, 0),
          ),
        );
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_today',
            cwd: '/tmp/project-alpha',
            title: '今天的普通对话',
            updatedAt: DateTime(2026, 11, 26, 12, 0),
          ),
        );
        sessCtrl.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_beta',
            cwd: '/tmp/project-beta',
            title: 'Beta 项目的对话',
            updatedAt: DateTime(2026, 11, 26, 11, 0),
          ),
          select: false,
        );

        await container
            .read(drawerViewProvider.notifier)
            .createFolder('核心任务', tint: 0, sessionIds: ['s_folder']);

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
                    now: fixedNow,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scope switcher displays active workspace, status filter chips are visible.
        expect(find.text('Alpha 项目'), findsOneWidget);
        expect(find.text('全部'), findsOneWidget);
        expect(find.text('运行中'), findsOneWidget);
        expect(find.text('待确认'), findsOneWidget);
        expect(find.text('未读'), findsOneWidget);
        expect(find.text('本机'), findsOneWidget);

        // Alpha scope shows Pinned -> Folder -> Today, hiding Beta's conversation!
        expect(find.text('置顶'), findsOneWidget);
        expect(find.text('置顶对话'), findsOneWidget);
        expect(find.text('核心任务'), findsOneWidget);
        expect(find.text('文件夹里的对话'), findsOneWidget);
        expect(find.text('今天'), findsOneWidget);
        expect(find.text('今天的普通对话'), findsOneWidget);
        expect(find.text('Beta 项目的对话'), findsNothing);

        // Tapping custom folder header collapses its conversations.
        await tester.tap(find.text('核心任务'));
        await tester.pumpAndSettle();
        expect(find.text('文件夹里的对话'), findsNothing);

        // Switching scope to 全部对话 reveals Beta's conversation too!
        await wsCtrl.select(null);
        await tester.pumpAndSettle();
        expect(find.text('全部对话'), findsOneWidget);
        expect(find.text('Beta 项目的对话'), findsOneWidget);

        // Entering multi-select swaps header & footer in place (DrawerSelectionHeader + SelectionActionBar).
        container.read(drawerSelectionProvider.notifier).start('s_today');
        await tester.pumpAndSettle();
        expect(find.text('全选'), findsOneWidget);
        expect(find.text('已选 1 个'), findsOneWidget);
        expect(find.text('完成'), findsOneWidget);
        expect(find.text('移到文件夹'), findsOneWidget);
        expect(find.text('归档'), findsOneWidget);
        expect(find.text('删除'), findsOneWidget);
      },
    );

    test(
      'decodes percent-encoded UTF-8 cwds from agy acp and keeps deleted workspaces & sessions gone after restart',
      () async {
        // 1. Percent-encoded Chinese + bracket paths (like %E5%86%AC%E6%97%A5...%5Bv.2.15%5D) decode cleanly.
        expect(
          normalizeWorkspacePath(
            'file:///storage/emulated/0/Download/%E5%86%AC%E6%97%A5%E7%8B%82%E6%83%B3%E6%9B%B2%20%5Bv.2.15%5D/',
          ),
          '/storage/emulated/0/Download/冬日狂想曲 [v.2.15]',
        );
        expect(
          normalizeWorkspacePath('/sdcard/%E6%B5%8B%E8%AF%95'),
          '/storage/emulated/0/测试',
        );

        final container1 = ProviderContainer();
        addTearDown(container1.dispose);
        // Let initial async _load finish before mutating.
        container1.read(workspacesProvider);
        container1.read(sessionsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        final ws1 = await container1
            .read(workspacesProvider.notifier)
            .add('/storage/emulated/0/Download/冬日狂想曲 [v.2.15]');
        final ws2 = await container1
            .read(workspacesProvider.notifier)
            .add('/storage/emulated/0/测试');

        // Register sessions arriving with percent-encoded cwds (as emitted by agy acp).
        final sess1 = container1.read(sessionsProvider.notifier);
        sess1.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_winter_1',
            cwd: '/storage/emulated/0/Download/%E5%86%AC%E6%97%A5%E7%8B%82%E6%83%B3%E6%9B%B2%20%5Bv.2.15%5D',
            title: '冬日对话 1',
            updatedAt: DateTime(2026, 11, 26, 10, 0),
          ),
        );
        sess1.registerCreatedSession(
          AcpSessionInfo(
            sessionId: 's_test_1',
            cwd: '/storage/emulated/0/%E6%B5%8B%E8%AF%95',
            title: '测试对话 1',
            updatedAt: DateTime(2026, 11, 26, 9, 0),
          ),
        );

        await container1.read(workspacesProvider.notifier).select(ws1.id);
        expect(
          container1
              .read(drawerScopeProvider)
              .sessions
              .map((s) => s.sessionId),
          ['s_winter_1'],
        );
        expect(container1.read(workspaceCountsProvider)[ws1.id], 1);
        expect(container1.read(workspaceCountsProvider)[ws2.id], 1);

        // 2. Remove workspace `测试` and its sessions, and delete `s_winter_1`.
        await container1.read(workspacesProvider.notifier).remove(ws2.id);
        await sess1.removeWorkspaceSessions(ws2.path);
        await sess1.deleteSession('s_winter_1');

        expect(container1.read(workspaceCountsProvider).containsKey(ws2.id), isFalse);
        expect(container1.read(workspaceCountsProvider)[ws1.id], 0);
        expect(container1.read(drawerScopeProvider).sessions, isEmpty);

        // 3. Simulate full app restart with a fresh ProviderContainer reading SharedPreferences.
        final container2 = ProviderContainer();
        addTearDown(container2.dispose);
        container2.read(workspacesProvider);
        container2.read(sessionsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Removed workspace `测试` does NOT come back after restart!
        final wsAfterRestart = container2.read(workspacesProvider);
        expect(wsAfterRestart.workspaces.any((w) => w.path.contains('测试')), isFalse);
        expect(wsAfterRestart.isPathRemoved('/storage/emulated/0/%E6%B5%8B%E8%AF%95'), isTrue);

        // Deleted session IDs survive restart and stay hidden even if present in state.
        final sessAfterRestart = container2.read(sessionsProvider);
        expect(sessAfterRestart.isDeleted('s_winter_1'), isTrue);
        expect(sessAfterRestart.isDeleted('s_test_1'), isTrue);
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

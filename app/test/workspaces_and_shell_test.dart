import 'package:agy_go/app.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/state/workspaces_state.dart';
import 'package:agy_go/ui/chat/empty_state.dart';
import 'package:agy_go/ui/features/all_features_page.dart';
import 'package:agy_go/ui/settings/settings_screen.dart';
import 'package:agy_go/ui/theme/theme.dart';
import 'package:agy_go/ui/workspace/workspaces_ui.dart';
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
      expect(find.text('手机存储挂载'), findsOneWidget);
      expect(find.text('工作区管理'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('外观与配色'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('外观与配色'), findsOneWidget);
    });

    testWidgets('AllFeaturesPage renders 2-column feature tiles', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: AllFeaturesPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部功能'), findsWidgets);
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
  });
}

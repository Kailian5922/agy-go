import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/agy_config_state.dart';
import 'package:agy_go/state/commands_state.dart';
import 'package:agy_go/state/sessions_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/ui/chat/diff_and_output_page.dart';
import 'package:agy_go/ui/chat/permission_controls.dart';
import 'package:agy_go/ui/features/agy_extensions_pages.dart';
import 'package:agy_go/ui/settings/settings_screen.dart';
import 'package:agy_go/ui/settings/settings_search_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Antigravity CLI slash command palette', () {
    test('parseSlashInput separates command token and arguments', () {
      expect(parseSlashInput('hello'), isNull);

      final bare = parseSlashInput('/plan');
      expect(bare, isNotNull);
      expect(bare!.token, 'plan');
      expect(bare.hasArgs, isFalse);

      final withArgs = parseSlashInput('  /goal finish tests');
      expect(withArgs, isNotNull);
      expect(withArgs!.token, 'goal');
      expect(withArgs.hasArgs, isTrue);
      expect(withArgs.rest, ' finish tests');
    });

    test('filterSlashCommands ranks prefix first and matches Chinese aliases', () {
      final permHits = filterSlashCommands(builtInAgySlashCommands, '审批');
      expect(permHits, isNotEmpty);
      expect(permHits.first.name, 'permissions');

      final planHits = filterSlashCommands(builtInAgySlashCommands, 'pl');
      expect(planHits.first.name, 'plan');

      final compactHits = filterSlashCommands(builtInAgySlashCommands, '压缩');
      expect(compactHits.first.name, 'compact');

      expect(
        resolveSlashCommand(builtInAgySlashCommands, 'rules')?.name,
        'memory',
      );
      expect(
        resolveSlashCommand(builtInAgySlashCommands, 'usage')?.name,
        'context',
      );
    });

    test('SlashPaletteContent switches from matches to argument hint', () {
      final matches = SlashPaletteContent.of(builtInAgySlashCommands, '/go');
      expect(matches, isA<SlashPaletteMatches>());
      expect((matches as SlashPaletteMatches).typed, isTrue);
      expect(matches.commands.first.name, 'goal');

      final hint = SlashPaletteContent.of(builtInAgySlashCommands, '/goal ');
      expect(hint, isA<SlashPaletteHint>());
      expect((hint as SlashPaletteHint).command.name, 'goal');

      final dismissed = SlashPaletteContent.of(
        builtInAgySlashCommands,
        '/goal build apk',
      );
      expect(dismissed, isNull);
    });
  });

  group('Antigravity CLI approval policy & settings persistence', () {
    test('migrates legacy agy.autoApproveCommands=true to alwaysProceed', () async {
      SharedPreferences.setMockInitialValues({'agy.autoApproveCommands': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final st = container.read(settingsProvider);
      expect(st.toolPermission, AgyToolPermission.alwaysProceed);
      expect(st.autoApproveCommands, isTrue);
    });

    test('persists agentMode, toolPermission, queuedBehavior, and wallpaper', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctrl = container.read(settingsProvider.notifier);
      await ctrl.setAgentMode(AgyAgentMode.plan);
      await ctrl.setToolPermission(AgyToolPermission.proceedInSandbox);
      await ctrl.setArtifactReviewPolicy(AgyArtifactReviewPolicy.alwaysProceed);
      await ctrl.setQueuedBehavior(AgyQueuedMessageBehavior.steer);
      await ctrl.setWallpaperPath('/tmp/bg.png');
      await ctrl.setWallpaperOpacity(0.35);

      final st = container.read(settingsProvider);
      expect(st.agentMode, AgyAgentMode.plan);
      expect(st.toolPermission, AgyToolPermission.proceedInSandbox);
      expect(st.artifactReviewPolicy, AgyArtifactReviewPolicy.alwaysProceed);
      expect(st.queuedBehavior, AgyQueuedMessageBehavior.steer);
      expect(st.wallpaperPath, '/tmp/bg.png');
      expect(st.wallpaperOpacity, closeTo(0.35, 0.001));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('agy.agentMode'), 'plan');
      expect(prefs.getString('agy.toolPermission'), 'proceed-in-sandbox');
      expect(prefs.getString('agy.queuedBehavior'), 'send-immediately');
    });
  });

  group('AGY config models & session folders', () {
    test('AgyMcpServerEntry and AgyPermissionRules JSON round-trip', () {
      const remote = AgyMcpServerEntry(
        name: 'context7',
        transport: 'http',
        url: 'https://mcp.example.com',
        headers: {'Authorization': 'Bearer test'},
      );
      final parsedRemote = AgyMcpServerEntry.fromJson(
        'context7',
        remote.toJson(),
      );
      expect(parsedRemote.transport, 'http');
      expect(parsedRemote.url, 'https://mcp.example.com');
      expect(parsedRemote.toAcpConfig(), isA<HttpMcpServerConfig>());

      const stdio = AgyMcpServerEntry(
        name: 'local-tool',
        transport: 'stdio',
        command: 'npx',
        args: ['-y', 'demo-server'],
      );
      final parsedStdio = AgyMcpServerEntry.fromJson(
        'local-tool',
        stdio.toJson(),
      );
      expect(parsedStdio.command, 'npx');
      expect(parsedStdio.args, ['-y', 'demo-server']);
      expect(parsedStdio.toAcpConfig(), isA<StdioMcpServerConfig>());

      const rules = AgyPermissionRules(
        allow: ['command(git)'],
        ask: ['command(rm)'],
        deny: ['write_file(.git/)'],
      );
      final parsedRules = AgyPermissionRules.fromJson(rules.toJson());
      expect(parsedRules.allow, ['command(git)']);
      expect(parsedRules.ask, ['command(rm)']);
      expect(parsedRules.deny, ['write_file(.git/)']);
    });

    test('SessionsController creates folders, moves, and batch archives/deletes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctrl = container.read(sessionsProvider.notifier);
      ctrl.registerCreatedSession(
        const AcpSessionInfo(sessionId: 's1', cwd: '/w', title: 'Alpha'),
      );
      ctrl.registerCreatedSession(
        const AcpSessionInfo(sessionId: 's2', cwd: '/w', title: 'Beta'),
      );

      await ctrl.createFolder('项目A');
      await ctrl.batchMoveToFolder({'s1', 's2'}, '项目A');
      expect(container.read(sessionsProvider).folders, contains('项目A'));
      expect(container.read(sessionsProvider).folderOf('s1'), '项目A');

      ctrl.selectFolder('项目A');
      expect(container.read(filteredSessionsProvider).length, 2);

      await ctrl.batchArchive({'s1'}, true);
      expect(container.read(sessionsProvider).isArchived('s1'), isTrue);

      await ctrl.batchDelete({'s2'});
      expect(
        container.read(sessionsProvider).sessions.map((s) => s.sessionId),
        ['s1'],
      );
    });
  });

  group('New parity UI pages render cleanly', () {
    testWidgets('PermissionPage displays official 4-tier Antigravity presets and plan toggle', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: PermissionPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('权限层级'), findsWidgets);
      expect(find.text('Antigravity 官方权限预设'), findsOneWidget);
      expect(find.text('严格确认'), findsOneWidget);
      expect(find.text('询问确认'), findsOneWidget);
      expect(find.text('沙箱放行'), findsOneWidget);
      expect(find.text('完全放行'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('默认开启计划模式（/plan）'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('默认开启计划模式（/plan）'), findsOneWidget);
    });

    testWidgets('ApprovalModeSheetBody renders inside Scaffold', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AgyGoApp(home: Scaffold(body: ApprovalModeSheetBody())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('权限层级'), findsOneWidget);
      expect(find.text('Antigravity 官方权限预设'), findsOneWidget);
      expect(find.text('严格确认'), findsOneWidget);
      expect(find.text('完全放行'), findsOneWidget);
      expect(find.text('计划模式（/plan）'), findsOneWidget);
    });

    testWidgets('McpServersPage, SkillsAndRulesPage, and SettingsSearchPage render', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: McpServersPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('MCP 服务管理'), findsWidgets);
      expect(find.text('phone（手机操控 MCP）'), findsOneWidget);

      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: SkillsAndRulesPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Skills 与记忆规则'), findsWidgets);

      await tester.pumpWidget(
        const ProviderScope(child: AgyGoApp(home: SettingsSearchPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('搜索设置'), findsWidgets);
      expect(find.textContaining('MCP 服务管理'), findsOneWidget);
    });

    testWidgets('DiffViewerPage and SelectTextPage render entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AgyGoApp(
            home: DiffViewerPage(
              entries: [
                DiffEntry(
                  path: 'lib/main.dart',
                  oldText: 'final a = 1;',
                  newText: 'final a = 2;\nfinal b = 3;',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('lib/main.dart'), findsOneWidget);

      await tester.pumpWidget(
        const ProviderScope(
          child: AgyGoApp(home: SelectTextPage(text: 'Hello Antigravity')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello Antigravity'), findsOneWidget);
    });
  });
}

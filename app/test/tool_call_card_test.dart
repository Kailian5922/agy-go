import 'package:acp_client/acp_client.dart';
import 'package:agy_go/ui/chat/tool_call_card.dart';
import 'package:agy_go/ui/chat/tool_format.dart';
import 'package:agy_go/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('tool_format path normalization & summary', () {
    test('collapses ../../../../../../ Android traversal paths and strips workspace prefix', () {
      const raw =
          '../../../../../../storage/emulated/0/game/冬日狂想曲 [v.2.15]/www/js/plugins.js';
      expect(
        normalizeToolPath(raw),
        '/storage/emulated/0/game/冬日狂想曲 [v.2.15]/www/js/plugins.js',
      );
      expect(
        displayToolPath(
          raw,
          workspaceCwd: '/storage/emulated/0/game/冬日狂想曲 [v.2.15]',
        ),
        'www/js/plugins.js',
      );
      // /sdcard alias matches /storage/emulated/0 workspace prefix cleanly.
      expect(
        displayToolPath(
          raw,
          workspaceCwd: '/sdcard/game/冬日狂想曲 [v.2.15]',
        ),
        'www/js/plugins.js',
      );
    });

    test('shortens external phone storage paths to /sdcard and middle-elides deep rows', () {
      const tc = AcpToolCall(
        toolCallId: 'tc_read_1',
        title:
            'File ../../../../../../storage/emulated/0/game/冬日狂想曲 [v.2.15]/www/js/plugins.js',
        kind: AcpToolKind.read,
        status: AcpToolStatus.completed,
      );

      expect(
        formatToolSummary(
          tc,
          workspaceCwd: '/storage/emulated/0/game/冬日狂想曲 [v.2.15]',
        ),
        'www/js/plugins.js',
      );
      expect(
        formatToolSummary(
          tc,
          workspaceCwd:
              '/data/user/0/io.github.kailian5922.agy_go/files/runtime/home/workspace',
        ),
        '/sdcard/…/js/plugins.js',
      );
      expect(
        formatToolSummary(
          tc,
          workspaceCwd:
              '/data/user/0/io.github.kailian5922.agy_go/files/runtime/home/workspace',
          compact: false,
        ),
        '/sdcard/game/冬日狂想曲 [v.2.15]/www/js/plugins.js',
      );
    });

    test('preserves line ranges and scrubs embedded traversal paths in shell commands', () {
      const rangedRead = AcpToolCall(
        toolCallId: 'tc_read_2',
        title:
            'Read File ../../../../../../storage/emulated/0/game/www/data/Map001.json (lines 1-80)',
        kind: AcpToolKind.read,
        status: AcpToolStatus.completed,
      );
      expect(
        formatToolSummary(
          rangedRead,
          workspaceCwd: '/storage/emulated/0/game',
        ),
        'www/data/Map001.json:1-80',
      );

      const shellCall = AcpToolCall(
        toolCallId: 'tc_exec_1',
        title: 'cat ../../../../../../storage/emulated/0/Download/note.txt',
        kind: AcpToolKind.execute,
        status: AcpToolStatus.completed,
      );
      expect(
        formatToolSummary(shellCall),
        'cat /sdcard/Download/note.txt',
      );
    });
  });

  testWidgets('ToolCallCard expands to reveal file location and inline diff', (
    tester,
  ) async {
    const toolCall = AcpToolCall(
      toolCallId: 'tc_diff_1',
      title: 'Edit main.dart',
      kind: AcpToolKind.edit,
      status: AcpToolStatus.completed,
      locations: [AcpToolLocation(path: 'lib/main.dart', line: 12)],
      content: [
        AcpDiffToolContent(
          path: 'lib/main.dart',
          oldText: 'print("old");',
          newText: 'print("new");',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(accent: AppAccent.mist, glassBlur: false),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ToolCallCard(toolCall: toolCall),
          ),
        ),
      ),
    );

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('+ print("new");'), findsNothing);

    await tester.tap(find.text('lib/main.dart'));
    await tester.pumpAndSettle();

    expect(find.text('lib/main.dart:12'), findsOneWidget);
    expect(find.text('- print("old");'), findsOneWidget);
    expect(find.text('+ print("new");'), findsOneWidget);
  });

  testWidgets(
    'ToolCallCard hides ../../../../../../ traversal noise and reveals full clean path on tap',
    (tester) async {
      const readCall = AcpToolCall(
        toolCallId: 'tc_read_ui',
        title:
            'File ../../../../../../storage/emulated/0/game/冬日狂想曲 [v.2.15]/www/js/plugins.js',
        kind: AcpToolKind.read,
        status: AcpToolStatus.completed,
        locations: [
          AcpToolLocation(
            path:
                '../../../../../../storage/emulated/0/game/冬日狂想曲 [v.2.15]/www/js/plugins.js',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(accent: AppAccent.mist, glassBlur: false),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ToolCallCard(
                toolCall: readCall,
                workspaceCwd:
                    '/data/user/0/io.github.kailian5922.agy_go/files/runtime/home/workspace',
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('../'), findsNothing);
      expect(find.text('/sdcard/…/js/plugins.js'), findsOneWidget);

      await tester.tap(find.text('/sdcard/…/js/plugins.js'));
      await tester.pumpAndSettle();

      expect(
        find.text('/sdcard/game/冬日狂想曲 [v.2.15]/www/js/plugins.js'),
        findsOneWidget,
      );
    },
  );

  group('Relative path titles, update_steps, paused status & non-text tool blocks', () {
    test('formats relative File titles with StartLine/EndLine and update_steps checklists', () {
      const relRead = AcpToolCall(
        toolCallId: 'tc_rel_read',
        name: 'read_file',
        title: 'File agy-go/README.md',
        kind: AcpToolKind.read,
        status: AcpToolStatus.inProgress,
        rawInput: {
          'Path': 'agy-go/README.md',
          'StartLine': 1,
          'EndLine': 25,
        },
      );
      expect(extractNativeToolLabel(relRead), isNull);
      expect(formatToolSummary(relRead), 'agy-go/README.md:1-25');
      expect(formatNativeToolLiveStatus(relRead), 'agy-go/README.md:1-25');

      // Descriptive English prose starting with "File " is NOT stripped as a bare path.
      const proseTool = AcpToolCall(
        toolCallId: 'tc_prose',
        title: 'File analysis complete',
        kind: AcpToolKind.other,
        status: AcpToolStatus.completed,
      );
      expect(extractNativeToolLabel(proseTool), 'File analysis complete');

      const planCall = AcpToolCall(
        toolCallId: 'tc_steps',
        name: 'update_steps',
        title: 'Run update_steps',
        kind: AcpToolKind.other,
        status: AcpToolStatus.completed,
        rawInput: {
          'steps': [
            {'title': 'Read source files', 'status': 'done'},
            {'title': 'Fix live UI sync', 'status': 'in_progress'},
          ],
        },
      );
      expect(extractNativeToolLabel(planCall), '计划 (1/2) · Fix live UI sync');
      expect(formatToolSummary(planCall), contains('1/2'));
      expect(formatToolSummary(planCall), contains('Fix live UI sync'));
      final details = formatToolInputDetails(planCall);
      expect(details, contains('✓ Read source files'));
      expect(details, contains('▸ Fix live UI sync'));

      const bareRunCall = AcpToolCall(
        toolCallId: 'tc_bare_run',
        name: 'read_file',
        title: 'Run read_file',
        kind: AcpToolKind.read,
        status: AcpToolStatus.inProgress,
      );
      expect(extractNativeToolLabel(bareRunCall), isNull);
    });

    testWidgets('ToolCallCard shows amber 待确认 badge when paused and expands rawInput arguments', (
      tester,
    ) async {
      const pausedExec = AcpToolCall(
        toolCallId: 'tc_paused_1',
        name: 'run_command',
        title: 'run_command',
        kind: AcpToolKind.execute,
        status: AcpToolStatus.paused,
        rawInput: {
          'CommandLine': 'git status --short',
          'Cwd': '/repo',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(accent: AppAccent.mist, glassBlur: false),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ToolCallCard(
                toolCall: pausedExec,
                workspaceCwd: '/repo',
              ),
            ),
          ),
        ),
      );

      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('git status --short'), findsOneWidget);

      await tester.tap(find.text('git status --short'));
      await tester.pumpAndSettle();

      expect(find.textContaining(r'$ git status --short'), findsOneWidget);
    });

    testWidgets('ToolCallCard renders AcpImageBlock and AcpResourceLinkBlock cleanly without toString leak', (
      tester,
    ) async {
      const mediaTool = AcpToolCall(
        toolCallId: 'tc_media_1',
        title: 'Capture screen',
        kind: AcpToolKind.other,
        status: AcpToolStatus.completed,
        content: [
          AcpBlockToolContent(
            AcpImageBlock(data: 'not-valid-base64', mimeType: 'image/png'),
          ),
          AcpBlockToolContent(
            AcpResourceLinkBlock(
              uri: 'file:///repo/docs/spec.md',
              name: 'spec.md',
              title: 'Architecture Spec',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(accent: AppAccent.mist, glassBlur: false),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ToolCallCard(toolCall: mediaTool),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Capture screen'));
      await tester.pumpAndSettle();

      expect(find.text('[图片: image/png]'), findsOneWidget);
      expect(find.textContaining('Architecture Spec'), findsOneWidget);
      expect(find.textContaining('Instance of'), findsNothing);
    });
  });
}

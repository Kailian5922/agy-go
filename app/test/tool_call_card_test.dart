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
}

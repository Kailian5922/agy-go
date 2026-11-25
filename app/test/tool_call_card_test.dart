import 'package:acp_client/acp_client.dart';
import 'package:agy_go/ui/chat/tool_call_card.dart';
import 'package:agy_go/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
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

    expect(find.text('Edit main.dart'), findsOneWidget);
    expect(find.text('+ print("new");'), findsNothing);

    await tester.tap(find.text('Edit main.dart'));
    await tester.pumpAndSettle();

    expect(find.text('lib/main.dart:12'), findsOneWidget);
    expect(find.text('- print("old");'), findsOneWidget);
    expect(find.text('+ print("new");'), findsOneWidget);
  });
}

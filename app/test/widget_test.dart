import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/ui/chat/permission_card.dart';
import 'package:agy_go/ui/theme/app_theme.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

void main() {
  testWidgets('AgyGoApp renders HomeShell and on-device install CTA', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AgyGoApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('AGY Go'), findsOneWidget);
    expect(find.text('一键安装本机引擎'), findsOneWidget);
  });

  testWidgets('PermissionCard renders options and dispatches selected optionId', (
    tester,
  ) async {
    final completer = Completer<AcpPermissionOutcome>();
    final pending = PendingPermission(
      id: 'p1',
      request: const AcpPermissionRequest(
        sessionId: 'sess_1',
        toolCall: AcpToolCall(
          toolCallId: 'tc_1',
          title: 'Run flutter test',
          kind: AcpToolKind.execute,
        ),
        options: [
          AcpPermissionOption(
            optionId: 'allow_once',
            name: '允许一次',
            kind: AcpPermissionOptionKind.allowOnce,
          ),
          AcpPermissionOption(
            optionId: 'reject_once',
            name: '拒绝',
            kind: AcpPermissionOptionKind.rejectOnce,
          ),
        ],
      ),
      completer: completer,
    );

    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAgyTheme(
          brightness: Brightness.dark,
          accentId: AppAccentId.nebula,
          glassBlur: false,
        ),
        home: Scaffold(
          body: PermissionCard(
            pending: pending,
            onSelect: (id) {
              picked = id;
              pending.select(id);
            },
            onCancel: pending.cancel,
          ),
        ),
      ),
    );

    expect(find.text('Run flutter test'), findsOneWidget);
    await tester.tap(find.text('允许一次'));
    await tester.pump();

    expect(picked, 'allow_once');
    final outcome = await completer.future;
    expect(outcome, isA<AcpPermissionSelected>());
    expect((outcome as AcpPermissionSelected).optionId, 'allow_once');
  });
}

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/share/conversation_export.dart';
import 'package:agy_go/state/pet_state.dart';
import 'package:agy_go/state/phone_state.dart';
import 'package:agy_go/state/system_state.dart';
import 'package:agy_go/ui/pet/starling_pet.dart';
import 'package:agy_go/ui/phone/phone_control_screen.dart';
import 'package:agy_go/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('ConversationExport redaction & replay round-trip', () {
    test('redacts Gemini API keys, OAuth tokens, and PEM keys', () {
      const dirty = '''
API key: AIzaSyD1234567890abcdefghijklmno
Token: ya29.a0AfH6SMC_super_secret_token_value
Authorization: Bearer my_secret_bearer_token_123456
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmU=
-----END OPENSSH PRIVATE KEY-----
''';
      final clean = ConversationExport.redactSecrets(dirty);
      expect(clean, isNot(contains('AIzaSyD1234567890')));
      expect(clean, isNot(contains('ya29.a0AfH6SMC')));
      expect(clean, isNot(contains('my_secret_bearer_token')));
      expect(clean, isNot(contains('b3BlbnNzaC1rZXktdjE')));
      expect(clean, contains('[REDACTED_GEMINI_KEY]'));
      expect(clean, contains('[REDACTED_OAUTH_TOKEN]'));
      expect(clean, contains('[REDACTED_PRIVATE_KEY]'));
    });

    test(
      'serializes and parses replay JSON bundle preserving turns and tool calls',
      () {
        final transcript = ChatTranscript(
          title: 'Demo Session',
          items: [
            UserTranscriptItem(
              id: 'u1',
              timestamp: DateTime.utc(2026, 11, 25, 12, 0),
              text: 'Check status with key AIzaSyD1234567890abcdefghijklmno',
            ),
            AssistantTranscriptItem(
              id: 'a1',
              timestamp: DateTime.utc(2026, 11, 25, 12, 1),
              thought: 'Checking repository',
              text: 'All checks passed.',
              toolCalls: const [
                AcpToolCall(
                  toolCallId: 'tc_1',
                  title: 'Run dart test',
                  kind: AcpToolKind.execute,
                  status: AcpToolStatus.completed,
                ),
              ],
            ),
          ],
        );

        final md = ConversationExport.toMarkdown(
          transcript,
          hostLabel: '本机引擎',
        );
        expect(md, contains('# Demo Session'));
        expect(md, contains('[REDACTED_GEMINI_KEY]'));
        expect(md, contains('Run dart test'));

        final jsonStr = ConversationExport.toReplayJson(transcript);
        final replayed = ConversationExport.parseReplayJson(jsonStr);
        expect(replayed.title, 'Demo Session');
        expect(replayed.items.length, 2);
        final user = replayed.items.first as UserTranscriptItem;
        expect(user.text, contains('[REDACTED_GEMINI_KEY]'));
        final assistant = replayed.items.last as AssistantTranscriptItem;
        expect(assistant.text, 'All checks passed.');
        expect(assistant.toolCalls.single.title, 'Run dart test');
      },
    );
  });

  group('SystemToolsController version comparison', () {
    test('detects strictly newer semantic versions', () {
      expect(SystemToolsController.isVersionNewer('v0.2.0', '0.1.0'), isTrue);
      expect(SystemToolsController.isVersionNewer('v0.1.1', '0.1.0'), isTrue);
      expect(SystemToolsController.isVersionNewer('v0.1.0', '0.1.0'), isFalse);
      expect(SystemToolsController.isVersionNewer('v0.0.9', '0.1.0'), isFalse);
    });
  });

  testWidgets('PhoneApprovalCard triggers approve and deny callbacks', (
    tester,
  ) async {
    var approved = false;
    var denied = false;
    const prompt = PhoneApprovalPrompt(
      id: 'req_1',
      tool: 'phone_tap',
      summary: '点击屏幕 (540, 1200)',
      riskLevel: 'protected',
      foregroundPackage: 'com.eg.android.AlipayGphone',
      reason: '当前位于受保护的金融/安全应用',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(accent: AppAccent.mist, glassBlur: false),
        home: Scaffold(
          body: PhoneApprovalCard(
            prompt: prompt,
            onApprove: () => approved = true,
            onDeny: () => denied = true,
          ),
        ),
      ),
    );

    expect(find.text('高风险手机操作确认'), findsOneWidget);
    await tester.tap(find.text('允许执行'));
    await tester.tap(find.text('拒绝'));
    expect(approved, isTrue);
    expect(denied, isTrue);
  });

  testWidgets('StarlingAvatar renders across all PetMood values', (
    tester,
  ) async {
    for (final mood in PetMood.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: StarlingAvatar(mood: mood, size: 64)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(StarlingAvatar), findsOneWidget);
    }
  });
}

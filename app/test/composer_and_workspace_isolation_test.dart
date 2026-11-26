import 'dart:io';

import 'package:acp_client/acp_client.dart';
import 'package:agy_go/app.dart';
import 'package:agy_go/state/chat_state.dart';
import 'package:agy_go/state/commands_state.dart';
import 'package:agy_go/state/settings_state.dart';
import 'package:agy_go/state/workspaces_state.dart';
import 'package:agy_go/ui/chat/chat_list.dart';
import 'package:agy_go/ui/chat/composer_bar.dart';
import 'package:agy_go/ui/shell/quick_panel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededChatController extends ChatController {
  _SeededChatController(this._initial);
  final ChatState _initial;

  @override
  ChatState build() => _initial;
}

void main() {
  const eventChannels = [
    MethodChannel('agy/runtime/events'),
    MethodChannel('agy/phone/events'),
    MethodChannel('agy/voice/events'),
  ];

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in eventChannels) {
      messenger.setMockMethodCallHandler(ch, (_) async => null);
    }
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in eventChannels) {
      messenger.setMockMethodCallHandler(ch, null);
    }
  });

  group('Composer / and @ autocomplete (ASCII + full-width Chinese IME)', () {
    test('parseSlashInput handles full-width Chinese slash ／ as well as /', () {
      final parsed = parseSlashInput('／usage');
      expect(parsed, isNotNull);
      expect(parsed!.token, 'usage');
      expect(parsed.hasArgs, isFalse);

      final withArgs = parseSlashInput('／goal finish tests');
      expect(withArgs, isNotNull);
      expect(withArgs!.token, 'goal');
      expect(withArgs.hasArgs, isTrue);
      expect(withArgs.rest, ' finish tests');
    });

    testWidgets(
      'ComposerBar opens & dismisses slash palette and scans nested workspace files for @ after Chinese text',
      (tester) async {
        final tmpDir = Directory.systemTemp.createTempSync('agy-mention-');
        addTearDown(() {
          if (tmpDir.existsSync()) {
            tmpDir.deleteSync(recursive: true);
          }
        });
        File('${tmpDir.path}/README.md').writeAsStringSync('# demo');
        Directory('${tmpDir.path}/src').createSync();
        File('${tmpDir.path}/src/main.dart').writeAsStringSync('void main() {}');
        Directory('${tmpDir.path}/save folder').createSync();
        File('${tmpDir.path}/save folder/slot 1.json').writeAsStringSync('{}');
        Directory('${tmpDir.path}/.git').createSync();
        File('${tmpDir.path}/.git/config').writeAsStringSync('[core]');

        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              effectiveWorkingDirProvider.overrideWith((_) => tmpDir.path),
            ],
            child: AgyGoApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ComposerBar(
                    controller: controller,
                    enabled: true,
                    isBusy: false,
                    onSend: (_) async {},
                    onCancel: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Full-width `／` opens slash palette, replacing with normal text dismisses it!
        controller.value = const TextEditingValue(
          text: '／us',
          selection: TextSelection.collapsed(offset: 3),
        );
        await tester.pumpAndSettle();
        expect(find.text('/context'), findsOneWidget);

        controller.value = const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        );
        await tester.pumpAndSettle();
        expect(find.text('/context'), findsNothing);

        // 2. Email address must NOT trigger @ file picker.
        controller.value = const TextEditingValue(
          text: 'test@example',
          selection: TextSelection.collapsed(offset: 12),
        );
        await tester.pumpAndSettle();
        expect(find.text('README.md'), findsNothing);

        // 3. Chinese text immediately followed by `@` triggers recursive workspace file scan!
        controller.value = const TextEditingValue(
          text: '帮我看看@',
          selection: TextSelection.collapsed(offset: 5),
        );
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.text('README.md').evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();

        expect(find.text('README.md'), findsOneWidget);
        expect(find.text('src/main.dart'), findsOneWidget);
        expect(find.text('save folder/slot 1.json'), findsOneWidget);
        expect(find.text('.git/config'), findsNothing);

        // 4. Picking a path with spaces quotes it cleanly & replaces full-width ＠ too.
        controller.value = const TextEditingValue(
          text: '读取＠slot',
          selection: TextSelection.collapsed(offset: 7),
        );
        await tester.pumpAndSettle();
        expect(find.text('save folder/slot 1.json'), findsOneWidget);

        await tester.tap(find.text('save folder/slot 1.json'));
        await tester.pumpAndSettle();
        expect(controller.text, '读取@"save folder/slot 1.json" ');
      },
    );
  });

  group('Workspace deletion & isolation', () {
    test(
      'default workspace can be removed, switches selection cleanly, and stays removed across restarts',
      () async {
        final c1 = ProviderContainer();
        addTearDown(c1.dispose);
        c1.read(workspacesProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Default allowNonWorkspaceAccess must be false for strict workspace isolation.
        expect(c1.read(settingsProvider).allowNonWorkspaceAccess, isFalse);

        final wsCtrl = c1.read(workspacesProvider.notifier);
        final realWs = await wsCtrl.add('/storage/emulated/0/game/demo');
        expect(
          c1.read(workspacesProvider).workspaces.any((w) => w.id == 'default'),
          isTrue,
        );

        // Remove built-in default workspace!
        await wsCtrl.remove('default');
        final afterRemove = c1.read(workspacesProvider);
        expect(afterRemove.workspaces.any((w) => w.id == 'default'), isFalse);
        expect(afterRemove.defaultRemoved, isTrue);
        expect(c1.read(effectiveWorkingDirProvider), realWs.path);

        // Simulate full app restart with fresh ProviderContainer.
        final c2 = ProviderContainer();
        addTearDown(c2.dispose);
        c2.read(workspacesProvider);
        await Future<void>.delayed(const Duration(milliseconds: 60));

        final afterRestart = c2.read(workspacesProvider);
        expect(afterRestart.workspaces.any((w) => w.id == 'default'), isFalse);
        expect(afterRestart.defaultRemoved, isTrue);
        expect(c2.read(effectiveWorkingDirProvider), realWs.path);
      },
    );
  });

  group('Tips & entrypoints accuracy', () {
    testWidgets('QuickPanel always displays quota entry even without an active session', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: AgyGoApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: QuickPanel(
                  motion: const AlwaysStoppedAnimation<double>(1.0),
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('订阅额度与上下文'), findsOneWidget);
    });

    testWidgets('Long-pressing user message bubble opens action sheet', (
      tester,
    ) async {
      final seeded = ChatState(
        sessionId: 's-1',
        transcript: ChatTranscript(
          items: [
            UserTranscriptItem(
              id: 'u1',
              text: '帮我查一下当前目录',
              timestamp: DateTime(2026, 11, 26, 15, 0),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatProvider.overrideWith(() => _SeededChatController(seeded)),
          ],
          child: AgyGoApp(
            home: Scaffold(
              body: ChatList(
                scrollController: ScrollController(),
                bottomInset: 80,
                onPickSuggestion: (_) {},
                onEditDraft: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('帮我查一下当前目录'));
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsOneWidget);
      expect(find.text('自由选字'), findsOneWidget);
      expect(find.text('引用追问'), findsOneWidget);
      expect(find.text('编辑并重发'), findsOneWidget);
    });
  });
}

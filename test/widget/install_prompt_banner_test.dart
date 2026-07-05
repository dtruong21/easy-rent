/// Tests widget pour [InstallPromptBanner].
library;

import 'package:easyrent/features/pwa/application/install_prompt_controller.dart';
import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:easyrent/features/pwa/presentation/install_prompt_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(InstallPromptState initialState) {
  return ProviderScope(
    overrides: [
      installPromptControllerProvider.overrideWith(
        (_) => _FakeController(initialState),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: InstallPromptBanner())),
  );
}

class _FakeController extends InstallPromptController {
  _FakeController(InstallPromptState initialState)
    : super(InstallPromptStorage()) {
    state = initialState;
  }
  bool triggerCalled = false;
  bool dismissCalled = false;

  @override
  Future<void> trigger() async {
    triggerCalled = true;
    state = const InstallPromptState.installed();
  }

  @override
  Future<void> dismiss() async {
    dismissCalled = true;
    state = const InstallPromptState.hidden();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('InstallPromptBanner — état hidden', () {
    testWidgets('rien n\'est affiché si état hidden', (tester) async {
      await tester.pumpWidget(_wrap(const InstallPromptState.hidden()));
      await tester.pumpAndSettle();
      expect(find.text('Installez Baillan.'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });
  });

  group('InstallPromptBanner — état visibleNative', () {
    testWidgets('affiche le banner natif', (tester) async {
      await tester.pumpWidget(_wrap(const InstallPromptState.visibleNative()));
      await tester.pump();
      expect(find.text('Installez Baillan.'), findsOneWidget);
      expect(find.text('Installer'), findsOneWidget);
    });

    testWidgets('tap "Installer" → trigger appelé', (tester) async {
      late _FakeController ctrl;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            installPromptControllerProvider.overrideWith((ref) {
              ctrl = _FakeController(const InstallPromptState.visibleNative());
              return ctrl;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: InstallPromptBanner())),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Installer'));
      await tester.pump();
      expect(ctrl.triggerCalled, isTrue);
    });

    testWidgets('tap bouton fermer → dismiss appelé', (tester) async {
      late _FakeController ctrl;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            installPromptControllerProvider.overrideWith((ref) {
              ctrl = _FakeController(const InstallPromptState.visibleNative());
              return ctrl;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: InstallPromptBanner())),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_banner_close')));
      await tester.pump();
      expect(ctrl.dismissCalled, isTrue);
    });
  });

  group('InstallPromptBanner — état visibleIos', () {
    testWidgets('affiche les instructions iOS', (tester) async {
      await tester.pumpWidget(_wrap(const InstallPromptState.visibleIos()));
      await tester.pump();
      expect(find.text('Installez Baillan.'), findsOneWidget);
      expect(find.text('OK, compris'), findsOneWidget);
    });
  });

  group('InstallPromptBanner — état triggering', () {
    testWidgets('affiche un indicateur de chargement', (tester) async {
      await tester.pumpWidget(_wrap(const InstallPromptState.triggering()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

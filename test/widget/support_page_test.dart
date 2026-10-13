/// Tests widget de [SupportPage].
///
/// Couvre :
/// - Titre + intro + champs + bouton présents
/// - Validation locale (bouton désactivé si sujet/message vide)
/// - Succès — repo appelé, snackbar, champs vidés
/// - Échec réseau — message inline neutre retentable
/// - État submitting
library;

import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/presentation/support_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ---------------------------------------------------------------------------
// Fake SupportRepository
// ---------------------------------------------------------------------------

/// Fake [SupportRepository] — enregistre le dernier appel pour assertion.
class _FakeSupportRepository implements SupportRepository {
  bool submitCalled = false;
  String? lastSubject;
  String? lastMessage;
  String? lastAppVersion;
  String? lastAppEnv;
  Exception? submitError;

  /// Si non-null, [submit] attend que ce [Completer] soit complété avant de
  /// retourner — permet d'observer l'état `submitting` dans les tests.
  Completer<void>? submitGate;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {
    submitCalled = true;
    lastSubject = subject;
    lastMessage = message;
    lastAppVersion = appVersion;
    lastAppEnv = appEnv;
    final gate = submitGate;
    if (gate != null) await gate.future;
    final err = submitError;
    if (err != null) throw err;
  }

  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildPage({_FakeSupportRepository? supportRepo}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SupportPage()),
    ],
  );

  return ProviderScope(
    overrides: [
      supportRepositoryProvider.overrideWithValue(
        supportRepo ?? _FakeSupportRepository(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Baillan',
      packageName: 'app.baillan',
      version: '1.0.0',
      buildNumber: '42',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('titre, intro, champs et bouton présents', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Nous contacter'), findsOneWidget);
    expect(find.text('Une question, un souci ? Écrivez-nous.'), findsOneWidget);
    expect(find.byKey(const Key('field_support_subject')), findsOneWidget);
    expect(find.byKey(const Key('field_support_message')), findsOneWidget);
    expect(find.byKey(const Key('btn_support_submit')), findsOneWidget);
  });

  testWidgets('bouton désactivé si sujet ou message vide', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('btn_support_submit')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets(
    'succès — repo appelé avec subject/message/appVersion/appEnv, snackbar, '
    'champs vidés',
    (tester) async {
      final supportRepo = _FakeSupportRepository();
      await tester.pumpWidget(_buildPage(supportRepo: supportRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_support_subject')),
        'Problème de quittance',
      );
      await tester.enterText(
        find.byKey(const Key('field_support_message')),
        'La quittance de mars ne se génère pas.',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_support_submit')));
      await tester.pumpAndSettle();

      expect(supportRepo.submitCalled, isTrue);
      expect(supportRepo.lastSubject, 'Problème de quittance');
      expect(supportRepo.lastMessage, 'La quittance de mars ne se génère pas.');
      expect(supportRepo.lastAppVersion, '1.0.0+42');
      expect(supportRepo.lastAppEnv, 'dev');

      expect(
        find.text('Message envoyé. Nous reviendrons vers vous par email.'),
        findsOneWidget,
      );

      final subjectField = tester.widget<TextFormField>(
        find.byKey(const Key('field_support_subject')),
      );
      expect(subjectField.controller?.text ?? '', isEmpty);
    },
  );

  testWidgets('échec réseau → message inline neutre retentable', (
    tester,
  ) async {
    final supportRepo = _FakeSupportRepository()
      ..submitError = Exception('network down');
    await tester.pumpWidget(_buildPage(supportRepo: supportRepo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field_support_subject')),
      'Sujet',
    );
    await tester.enterText(
      find.byKey(const Key('field_support_message')),
      'Message',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn_support_submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Envoi impossible. Réessayez dans quelques instants.'),
      findsOneWidget,
    );
    // Retentable : le bouton redevient actif (les champs n'ont pas été
    // vidés, l'utilisateur peut relancer).
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('btn_support_submit')),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('bouton désactivé pendant submit', (tester) async {
    final gate = Completer<void>();
    final supportRepo = _FakeSupportRepository()..submitGate = gate;
    await tester.pumpWidget(_buildPage(supportRepo: supportRepo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field_support_subject')),
      'Sujet',
    );
    await tester.enterText(
      find.byKey(const Key('field_support_message')),
      'Message',
    );
    await tester.pump();

    await tester.pumpAndSettle();
    // Le submit reste bloqué sur `gate.future` après ce await (même
    // stratégie que la page mot de passe).
    await tester.tap(find.byKey(const Key('btn_support_submit')));
    await tester.pump();

    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('btn_support_submit')),
    );
    expect(btn.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });
}

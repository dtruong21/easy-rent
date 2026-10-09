/// Tests widget pour [AppReviewPrompt] (FEAT-060).
library;

import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/features/app_review/application/review_eligibility_provider.dart';
import 'package:easyrent/features/app_review/data/review_solicitation_storage.dart';
import 'package:easyrent/features/app_review/data/store_review_service.dart';
import 'package:easyrent/features/app_review/presentation/app_review_prompt.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeStorage implements ReviewSolicitationStorage {
  _FakeStorage({this.failMark = false});

  final bool failMark;
  final marked = <DateTime>[];

  @override
  Future<DateTime?> readLastSolicitedAt() async => null;

  @override
  Future<void> markSolicited(DateTime at) async {
    if (failMark) throw StateError('storage down');
    marked.add(at);
  }
}

class _FakeStoreService implements StoreReviewService {
  _FakeStoreService({this.available = true, this.gate, this.failWith});

  final bool available;

  /// Si fourni, [requestReview] attend sa complétion (fenêtre Play en cours).
  final Completer<void>? gate;

  /// Si fourni, [requestReview] lève cette erreur.
  final Object? failWith;
  int isAvailableCalls = 0;
  int requestReviewCalls = 0;

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls++;
    return available;
  }

  @override
  Future<void> requestReview() async {
    requestReviewCalls++;
    if (failWith != null) throw failWith!;
    await gate?.future;
  }

  @override
  Future<void> openStoreListing({String? appStoreId}) async {}
}

final _now = DateTime(2026, 10, 9);

void main() {
  late _FakeStorage storage;
  late _FakeStoreService service;
  var showPrompt = true;

  Future<void> pumpPrompt(
    WidgetTester tester, {
    required bool eligible,
    bool storeApp = false,
    bool available = true,
    Completer<void>? gate,
    Object? failWith,
    bool failMark = false,
  }) async {
    debugIsStoreAppOverride = storeApp;
    addTearDown(() => debugIsStoreAppOverride = false);
    showPrompt = true;
    storage = _FakeStorage(failMark: failMark);
    service = _FakeStoreService(
      available: available,
      gate: gate,
      failWith: failWith,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  // Reconstruction du parent / démontage du prompt.
                  TextButton(
                    key: const Key('rebuild'),
                    onPressed: () => setState(() {}),
                    child: const Text('rebuild'),
                  ),
                  TextButton(
                    key: const Key('unmount'),
                    onPressed: () => setState(() => showPrompt = false),
                    child: const Text('unmount'),
                  ),
                  // Non const : sinon Flutter saute la reconstruction de
                  // l'enfant et le garde « une fois par montage » n'est
                  // jamais exercé.
                  // ignore: prefer_const_constructors
                  if (showPrompt) AppReviewPrompt(),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/feedback',
          builder: (_, _) => const Text('feedback-page'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewEligibilityProvider.overrideWith((ref) async => eligible),
          reviewSolicitationStorageProvider.overrideWithValue(storage),
          storeReviewServiceProvider.overrideWithValue(service),
          reviewClockProvider.overrideWithValue(() => _now),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final card = find.byKey(const Key('card_review_invite'));

  testWidgets('web éligible : carte visible, aucun appel au service store', (
    tester,
  ) async {
    await pumpPrompt(tester, eligible: true);

    expect(card, findsOneWidget);
    expect(find.text('Votre avis compte'), findsOneWidget);
    expect(service.isAvailableCalls, 0);
    expect(service.requestReviewCalls, 0);
  });

  testWidgets('web non éligible : aucune carte', (tester) async {
    await pumpPrompt(tester, eligible: false);

    expect(card, findsNothing);
  });

  testWidgets('web : « Donner mon avis » enregistre puis ouvre le formulaire', (
    tester,
  ) async {
    await pumpPrompt(tester, eligible: true);

    await tester.tap(find.byKey(const Key('btn_review_invite_feedback')));
    await tester.pumpAndSettle();

    expect(storage.marked, [_now]);
    expect(find.text('feedback-page'), findsOneWidget);
  });

  testWidgets(
    'web : un échec de stockage n\'empêche pas d\'ouvrir le formulaire',
    (tester) async {
      await pumpPrompt(tester, eligible: true, failMark: true);

      await tester.tap(find.byKey(const Key('btn_review_invite_feedback')));
      await tester.pumpAndSettle();

      expect(find.text('feedback-page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('web : la croix enregistre et masque la carte', (tester) async {
    await pumpPrompt(tester, eligible: true);

    await tester.tap(find.byKey(const Key('btn_review_invite_close')));
    await tester.pumpAndSettle();

    expect(storage.marked, [_now]);
    expect(card, findsNothing);
  });

  testWidgets(
    'app store éligible et disponible : demande native, pas de carte',
    (tester) async {
      await pumpPrompt(tester, eligible: true, storeApp: true);

      expect(service.requestReviewCalls, 1);
      expect(storage.marked, [_now]);
      expect(card, findsNothing);
    },
  );

  testWidgets('app store éligible mais indisponible : ni demande ni date', (
    tester,
  ) async {
    await pumpPrompt(tester, eligible: true, storeApp: true, available: false);

    expect(service.requestReviewCalls, 0);
    expect(storage.marked, isEmpty);
    expect(card, findsNothing);
  });

  testWidgets('app store non éligible : aucun appel', (tester) async {
    await pumpPrompt(tester, eligible: false, storeApp: true);

    expect(service.isAvailableCalls, 0);
    expect(service.requestReviewCalls, 0);
    expect(storage.marked, isEmpty);
    expect(card, findsNothing);
  });

  testWidgets('app store : une reconstruction ne relance pas la demande', (
    tester,
  ) async {
    await pumpPrompt(tester, eligible: true, storeApp: true);
    expect(service.requestReviewCalls, 1);

    // Reconstruction du parent (le prompt n'est pas const : son build rejoue).
    await tester.tap(find.byKey(const Key('rebuild')));
    await tester.pumpAndSettle();
    // Nouvelle émission de l'éligibilité : le build du prompt rejoue aussi.
    ProviderScope.containerOf(
      tester.element(find.byType(AppReviewPrompt)),
    ).invalidate(reviewEligibilityProvider);
    await tester.pumpAndSettle();

    expect(service.requestReviewCalls, 1);
    expect(storage.marked, [_now]);
  });

  testWidgets('app store : démontage pendant la fenêtre, la date est '
      'quand même enregistrée sans erreur', (tester) async {
    final gate = Completer<void>();
    await pumpPrompt(tester, eligible: true, storeApp: true, gate: gate);
    expect(service.requestReviewCalls, 1);
    expect(storage.marked, isEmpty);

    await tester.tap(find.byKey(const Key('unmount')));
    await tester.pumpAndSettle();
    expect(find.byType(AppReviewPrompt), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(storage.marked, [_now]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app store : une erreur du service est journalisée, pas levée', (
    tester,
  ) async {
    await pumpPrompt(
      tester,
      eligible: true,
      storeApp: true,
      failWith: StateError('boom'),
    );

    expect(service.requestReviewCalls, 1);
    expect(storage.marked, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

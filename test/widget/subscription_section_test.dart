/// Tests widget pour [SubscriptionSection] (FEAT-044f).
///
/// Utilise un fake [SubscriptionRepository] (jamais d'appel réseau) et une
/// override directe de [landlordTierProvider] — pas de dépendance à
/// `authStateChangesProvider`/Firebase (même convention que
/// `anon_demo_banner_test.dart`).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/data/subscription_repository.dart';
import 'package:easyrent/features/paid_plan/presentation/widgets/subscription_section.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository({this.cancelException, this.reactivateException});

  final Exception? cancelException;
  final Exception? reactivateException;

  int cancelCallCount = 0;
  int reactivateCallCount = 0;

  @override
  Future<void> cancel() async {
    cancelCallCount++;
    if (cancelException != null) throw cancelException!;
  }

  @override
  Future<void> reactivate() async {
    reactivateCallCount++;
    if (reactivateException != null) throw reactivateException!;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildApp({
  required LandlordTierSnapshot? snapshot,
  required SubscriptionRepository repo,
}) {
  return ProviderScope(
    overrides: [
      landlordTierProvider.overrideWith((ref) => Stream.value(snapshot)),
      subscriptionRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: const Scaffold(body: SubscriptionSection()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SubscriptionSection — visibilité selon le tier', () {
    testWidgets('tier free → section absente (aucun bouton, aucun titre)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: const LandlordTierSnapshot(tier: SubscriptionTier.free),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abonnement Baillan Pro'), findsNothing);
      expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
      expect(
        find.byKey(const Key('btn_subscription_reactivate')),
        findsNothing,
      );
    });

    testWidgets('tier anonymous → section absente', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: const LandlordTierSnapshot(
            tier: SubscriptionTier.anonymous,
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abonnement Baillan Pro'), findsNothing);
    });
  });

  group('SubscriptionSection — paid + web', () {
    testWidgets(
      'proWillRenew == true → bouton "Résilier" + libellé renouvellement',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 8, 15),
              proStore: 'web',
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_subscription_cancel')),
          findsOneWidget,
        );
        expect(find.textContaining('15/08/2026'), findsOneWidget);
        expect(
          find.byKey(const Key('btn_subscription_reactivate')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'proWillRenew == false → "Pro jusqu\'au …, puis Gratuit" + bouton "Réactiver"',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: false,
              proExpiresAt: DateTime(2026, 9, 1),
              proStore: 'web',
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_subscription_reactivate')),
          findsOneWidget,
        );
        expect(find.textContaining('puis Gratuit'), findsOneWidget);
        expect(find.textContaining('01/09/2026'), findsOneWidget);
        expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
      },
    );

    testWidgets('proStore null (inconnu) → traité comme web, bouton Résilier', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: true,
            proExpiresAt: DateTime(2026, 8, 15),
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_subscription_cancel')), findsOneWidget);
    });
  });

  group('SubscriptionSection — paid + store mobile', () {
    testWidgets('proStore == app_store → message store, aucun bouton', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: true,
            proStore: 'app_store',
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('txt_subscription_manage_on_store')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
      expect(
        find.byKey(const Key('btn_subscription_reactivate')),
        findsNothing,
      );
    });

    testWidgets('proStore == play_store → message store, aucun bouton', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: true,
            proStore: 'play_store',
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('txt_subscription_manage_on_store')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
    });
  });

  group('SubscriptionSection — flux de résiliation', () {
    testWidgets(
      'tap Résilier → dialog affiché → Confirmer appelle repo.cancel() + snackbar succès',
      (tester) async {
        final repo = _FakeSubscriptionRepository();
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 8, 15),
              proStore: 'web',
            ),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_subscription_cancel')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('dialog_subscription_cancel')),
          findsOneWidget,
        );
        // Récapitulatif L215-1-1 : la date de fin d'accès apparaît dans le
        // corps du dialog.
        expect(find.textContaining('15/08/2026'), findsWidgets);

        await tester.tap(
          find.byKey(const Key('btn_subscription_cancel_confirm')),
        );
        await tester.pumpAndSettle();

        expect(repo.cancelCallCount, 1);
        expect(
          find.byKey(const Key('snackbar_subscription_success')),
          findsOneWidget,
        );
      },
    );

    testWidgets('dialog annulé → repo.cancel() jamais appelé', (tester) async {
      final repo = _FakeSubscriptionRepository();
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: true,
            proExpiresAt: DateTime(2026, 8, 15),
            proStore: 'web',
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_subscription_cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.cancelCallCount, 0);
      expect(find.byKey(const Key('dialog_subscription_cancel')), findsNothing);
    });

    testWidgets(
      'repo.cancel() lève NoActiveWebSubscriptionException → snackbar erreur mappée',
      (tester) async {
        final repo = _FakeSubscriptionRepository(
          cancelException: const NoActiveWebSubscriptionException(),
        );
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 8, 15),
              proStore: 'web',
            ),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_subscription_cancel')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('btn_subscription_cancel_confirm')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('snackbar_subscription_error')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Aucun abonnement web actif'),
          findsOneWidget,
        );
      },
    );

    testWidgets('tap Réactiver → repo.reactivate() appelé + snackbar succès', (
      tester,
    ) async {
      final repo = _FakeSubscriptionRepository();
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: false,
            proExpiresAt: DateTime(2026, 9, 1),
            proStore: 'web',
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_subscription_reactivate')));
      await tester.pumpAndSettle();

      expect(repo.reactivateCallCount, 1);
      expect(
        find.byKey(const Key('snackbar_subscription_success')),
        findsOneWidget,
      );
    });

    testWidgets(
      'repo.reactivate() lève une erreur non mappée → snackbar erreur générique',
      (tester) async {
        final repo = _FakeSubscriptionRepository(
          reactivateException: const SubscriptionException('boom'),
        );
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: false,
              proExpiresAt: DateTime(2026, 9, 1),
              proStore: 'web',
            ),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_subscription_reactivate')));
        await tester.pumpAndSettle();

        expect(repo.reactivateCallCount, 1);
        expect(
          find.byKey(const Key('snackbar_subscription_error')),
          findsOneWidget,
        );
        expect(find.textContaining('Une erreur est survenue'), findsOneWidget);
      },
    );
  });
}

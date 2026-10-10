/// Tests widget pour [SubscriptionSection] (FEAT-044f).
///
/// Utilise un fake [SubscriptionRepository] (jamais d'appel réseau) et une
/// override directe de [landlordTierProvider] — pas de dépendance à
/// `authStateChangesProvider`/Firebase (même convention que
/// `anon_demo_banner_test.dart`).
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/data/subscription_repository.dart';
import 'package:easyrent/features/paid_plan/presentation/widgets/subscription_section.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../helpers/fake_store_billing_service.dart';

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

  @override
  Future<void> changePlan({
    required String level,
    required String period,
  }) async {
    throw UnimplementedError('not exercised by these tests');
  }

  @override
  Future<String?> currentBillingPeriod() async =>
      throw UnimplementedError('not exercised by these tests');
}

/// Lanceur d'URL factice : enregistre les URL ouvertes (cf. tenant_card_test).
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => result;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return result;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildApp({
  required LandlordTierSnapshot? snapshot,
  required SubscriptionRepository repo,
  StoreBillingService? storeBilling,
}) {
  return ProviderScope(
    overrides: [
      landlordTierProvider.overrideWith((ref) => Stream.value(snapshot)),
      subscriptionRepositoryProvider.overrideWithValue(repo),
      if (storeBilling != null)
        storeBillingServiceProvider.overrideWithValue(storeBilling),
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

  group('SubscriptionSection — palier réel (FEAT-056)', () {
    testWidgets('planLevel=max → titre "Abonnement Max"', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            planLevel: 'max',
            proWillRenew: true,
            proExpiresAt: DateTime(2026, 8, 15),
            proStore: 'web',
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abonnement Max'), findsOneWidget);
      expect(find.text('Abonnement Baillan Pro'), findsNothing);
    });

    testWidgets(
      'planLevel absent (legacy) → grandfathering I3, titre "Abonnement Pro"',
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

        expect(find.text('Abonnement Pro'), findsOneWidget);
      },
    );

    testWidgets(
      'planLevel=max, résiliation programmée → "Max jusqu\'au …, puis Gratuit" (jamais "Pro")',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              planLevel: 'max',
              proWillRenew: false,
              proExpiresAt: DateTime(2026, 9, 1),
              proStore: 'web',
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Max jusqu\'au'), findsOneWidget);
        expect(find.textContaining('Pro jusqu\'au'), findsNothing);
      },
    );

    testWidgets('abonné web → bouton "Changer d\'offre" présent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            planLevel: 'pro',
            proWillRenew: true,
            proExpiresAt: DateTime(2026, 8, 15),
            proStore: 'web',
          ),
          repo: _FakeSubscriptionRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('btn_subscription_change_plan')),
        findsOneWidget,
      );
    });

    testWidgets(
      'abonné store mobile → bouton "Changer d\'offre" masqué (self-service web uniquement)',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              planLevel: 'pro',
              proWillRenew: true,
              proStore: 'app_store',
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_subscription_change_plan')),
          findsNothing,
        );
      },
    );
  });

  group('SubscriptionSection — paid + store mobile', () {
    late _FakeUrlLauncher launcher;
    late UrlLauncherPlatform previousLauncher;
    late FakeStoreBillingService fake;

    setUp(() {
      previousLauncher = UrlLauncherPlatform.instance;
      launcher = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      fake = FakeStoreBillingService();
    });

    tearDown(() => UrlLauncherPlatform.instance = previousLauncher);

    Future<void> pumpStore(WidgetTester tester, String store) async {
      await tester.pumpWidget(
        _buildApp(
          snapshot: LandlordTierSnapshot(
            tier: SubscriptionTier.paid,
            proWillRenew: true,
            proStore: store,
          ),
          repo: _FakeSubscriptionRepository(),
          storeBilling: fake,
        ),
      );
      await tester.pumpAndSettle();
    }

    void expectStoreOnly(String label) {
      expect(
        find.byKey(const Key('txt_subscription_manage_on_store')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('btn_subscription_manage_in_store')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      // Aucun chemin Stripe pour un abonné store.
      expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
      expect(
        find.byKey(const Key('btn_subscription_reactivate')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('btn_subscription_change_plan')),
        findsNothing,
      );
    }

    testWidgets(
      'proStore == app_store → message store + bouton « Gérer dans App Store »',
      (tester) async {
        await pumpStore(tester, 'app_store');
        expectStoreOnly('Gérer dans App Store');
      },
    );

    testWidgets(
      'proStore == play_store → message store + bouton « Gérer dans Google Play »',
      (tester) async {
        await pumpStore(tester, 'play_store');
        expectStoreOnly('Gérer dans Google Play');
      },
    );

    testWidgets('app_store sans URL RevenueCat → page générique App Store', (
      tester,
    ) async {
      fake.management = null;
      await pumpStore(tester, 'app_store');

      await tester.tap(
        find.byKey(const Key('btn_subscription_manage_in_store')),
      );
      await tester.pumpAndSettle();

      expect(launcher.launched, [
        'https://apps.apple.com/account/subscriptions',
      ]);
    });

    testWidgets('play_store sans URL RevenueCat → page générique Google Play', (
      tester,
    ) async {
      fake.management = null;
      await pumpStore(tester, 'play_store');

      await tester.tap(
        find.byKey(const Key('btn_subscription_manage_in_store')),
      );
      await tester.pumpAndSettle();

      expect(launcher.launched, [
        'https://play.google.com/store/account/subscriptions',
      ]);
    });

    testWidgets('URL RevenueCat connue → cette URL est ouverte', (
      tester,
    ) async {
      fake.management = Uri.parse('https://example.test/manage');
      await pumpStore(tester, 'app_store');

      await tester.tap(
        find.byKey(const Key('btn_subscription_manage_in_store')),
      );
      await tester.pumpAndSettle();

      expect(launcher.launched, ['https://example.test/manage']);
    });

    testWidgets('lanceur d\'URL en échec → aucune erreur non gérée', (
      tester,
    ) async {
      launcher.result = false;
      await pumpStore(tester, 'app_store');

      await tester.tap(
        find.byKey(const Key('btn_subscription_manage_in_store')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
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

  group('SubscriptionSection — app store (iOS/Android)', () {
    setUp(() => debugIsStoreAppOverride = true);
    tearDown(() => debugIsStoreAppOverride = false);

    testWidgets(
      'abonnement web actif → statut + résiliation conservés, pas de « Changer d\'offre »',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 9, 1),
              proStore: 'web',
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('txt_subscription_status')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_subscription_cancel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_subscription_change_plan')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'abonnement web sans origine connue (null) → résiliation conservée, pas de « Changer d\'offre »',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 9, 1),
            ),
            repo: _FakeSubscriptionRepository(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_subscription_cancel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_subscription_change_plan')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'abonnement web résilié (fin programmée) → statut affiché, « Réactiver » masqué',
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
          find.byKey(const Key('txt_subscription_status')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_subscription_reactivate')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('btn_subscription_change_plan')),
          findsNothing,
        );
      },
    );

    for (final store in ['app_store', 'play_store']) {
      testWidgets('abonnement $store → message store + bouton Gérer', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildApp(
            snapshot: LandlordTierSnapshot(
              tier: SubscriptionTier.paid,
              proWillRenew: true,
              proExpiresAt: DateTime(2026, 9, 1),
              proStore: store,
            ),
            repo: _FakeSubscriptionRepository(),
            storeBilling: FakeStoreBillingService(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('txt_subscription_manage_on_store')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_subscription_manage_in_store')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('btn_subscription_cancel')), findsNothing);
        expect(
          find.byKey(const Key('btn_subscription_reactivate')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('btn_subscription_change_plan')),
          findsNothing,
        );
      });
    }
  });
}

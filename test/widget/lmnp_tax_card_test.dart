/// Tests widget de [LmnpTaxCard] (FEAT-061) : carte Pro, variante verrouillée.
library;

import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/utils/money_format.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/widgets/lmnp_tax_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

InvestmentScenario _caseA({int rent = 60000}) => InvestmentScenario(
  id: 't',
  landlordId: 'l',
  name: 't',
  purchasePriceCents: 10000000,
  notaryFeesCents: 800000,
  furnitureCents: 700000,
  landSharePercent: 20,
  monthlyRentHcCents: rent,
  propertyTaxAnnualCents: 80000,
  insurancePnoAnnualCents: 15000,
  tmiPercent: 30,
  isFurnished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const _pro = LandlordTierSnapshot(
  tier: SubscriptionTier.paid,
  planLevel: 'pro',
);
const _free = LandlordTierSnapshot(tier: SubscriptionTier.free);

Future<void> _pump(
  WidgetTester tester,
  InvestmentScenario s,
  LandlordTierSnapshot tier,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(child: LmnpTaxCard(scenario: s)),
        ),
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) => const Scaffold(body: Text('PRO PAGE')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        landlordTierProvider.overrideWith((ref) => Stream.value(tier)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        locale: const Locale('fr'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _eur(int cents) => MoneyFormat.formatEurosFromCents(cents);

void main() {
  tearDown(() => debugIsStoreAppOverride = null);

  testWidgets('tier en chargement : ni carte verrouillée ni carte Pro', (
    tester,
  ) async {
    final ctrl = StreamController<LandlordTierSnapshot>();
    addTearDown(ctrl.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [landlordTierProvider.overrideWith((ref) => ctrl.stream)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: supportedLocales,
          locale: const Locale('fr'),
          home: Scaffold(body: LmnpTaxCard(scenario: _caseA())),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('lmnp_locked')), findsNothing);
    expect(find.byKey(const Key('lmnp_micro_total')), findsNothing);
  });

  group('LmnpTaxCard — Pro', () {
    testWidgets('totaux micro / réel, badge, règles, tableau annuel', (
      tester,
    ) async {
      await _pump(tester, _caseA(), _pro);
      expect(
        tester.widget<Text>(find.byKey(const Key('lmnp_micro_total'))).data,
        _eur(1749600),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('lmnp_reel_total'))).data,
        _eur(1012500),
      );
      expect(find.byKey(const Key('lmnp_best_badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('lmnp_reel_column')),
          matching: find.byKey(const Key('lmnp_best_badge')),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Règles 2026'), findsOneWidget);
      expect(find.byKey(const Key('lmnp_locked')), findsNothing);

      expect(find.byKey(const Key('lmnp_yearly_table')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('lmnp_yearly_toggle')));
      await tester.tap(find.byKey(const Key('lmnp_yearly_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lmnp_yearly_table')), findsOneWidget);
    });

    testWidgets('avertissements : revente + réforme toujours, pas LMP', (
      tester,
    ) async {
      await _pump(tester, _caseA(), _pro);
      expect(find.byKey(const Key('lmnp_warning_resale')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_warning_reform')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_warning_lmp')), findsNothing);
      expect(find.byKey(const Key('lmnp_micro_unavailable')), findsNothing);
    });

    testWidgets('loyers > 23 000 € : alerte LMP', (tester) async {
      await _pump(tester, _caseA(rent: 200000), _pro);
      expect(find.byKey(const Key('lmnp_warning_lmp')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_micro_unavailable')), findsNothing);
    });

    testWidgets('loyers > plafond micro : micro non disponible', (
      tester,
    ) async {
      await _pump(tester, _caseA(rent: 700000), _pro);
      expect(find.byKey(const Key('lmnp_micro_unavailable')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_micro_total')), findsNothing);
      expect(find.byKey(const Key('lmnp_warning_lmp')), findsOneWidget);
    });
  });

  group('LmnpTaxCard — gratuit', () {
    testWidgets('verrouillée, aucun montant, bouton Pro si achat possible', (
      tester,
    ) async {
      debugIsStoreAppOverride = false;
      await _pump(tester, _caseA(), _free);
      expect(find.byKey(const Key('lmnp_locked')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_micro_total')), findsNothing);
      expect(find.byKey(const Key('lmnp_reel_total')), findsNothing);
      await tester.tap(find.byKey(const Key('lmnp_upgrade_button')));
      await tester.pumpAndSettle();
      expect(find.text('PRO PAGE'), findsOneWidget);
    });

    testWidgets('app store sans achat intégré : pas de bouton', (tester) async {
      debugIsStoreAppOverride = true;
      await _pump(tester, _caseA(), _free);
      expect(find.byKey(const Key('lmnp_locked')), findsOneWidget);
      expect(find.byKey(const Key('lmnp_upgrade_button')), findsNothing);
    });
  });
}

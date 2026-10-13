/// Tests unitaires + widget pour la section « Rentabilité portfolio » du
/// dashboard.
///
/// Verrou de régression : [computePortfolioYield] déclarait des numérateurs
/// pondérés jamais incrémentés — la division rendait donc systématiquement
/// 0,00 % quels que soient les biens saisis, et le cash flow était codé en
/// dur à `null`. Ces tests figent le calcul réel (délégué à
/// [computeSnapshotForProperty], le même moteur que la fiche d'un bien).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/portfolio_yield_section.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty({
  required String id,
  int? purchasePriceCents,
  int? propertyTaxAnnualCents,
  int? insurancePnoAnnualCents,
  int? condoFeesNonRecoverableCents,
}) => Property(
  id: id,
  landlordId: 'owner',
  name: 'Bien $id',
  address: '1 rue Test, 75001 Paris',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  purchasePriceCents: purchasePriceCents,
  propertyTaxAnnualCents: propertyTaxAnnualCents,
  insurancePnoAnnualCents: insurancePnoAnnualCents,
  condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
);

PropertyListItem _makeItem({
  required String id,
  int? purchasePriceCents,
  String? activeLeaseId,
  int? rentHcCents,
  int? propertyTaxAnnualCents,
  int? insurancePnoAnnualCents,
  int? condoFeesNonRecoverableCents,
}) => PropertyListItem(
  property: _makeProperty(
    id: id,
    purchasePriceCents: purchasePriceCents,
    propertyTaxAnnualCents: propertyTaxAnnualCents,
    insurancePnoAnnualCents: insurancePnoAnnualCents,
    condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
  ),
  activeLeaseId: activeLeaseId,
  currentRentHcCents: rentHcCents,
);

// ---------------------------------------------------------------------------
// Fake repository — pour les tests widget
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  const _FakeRepo(this.items);

  final List<PropertyListItem> items;

  @override
  Future<List<Property>> list() async => items.map((i) => i.property).toList();

  @override
  Future<List<PropertyListItem>> listWithLeases() async => items;

  @override
  Future<Property> getById(String id) async => items.first.property;

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

Widget _wrap(List<PropertyListItem> items) {
  return ProviderScope(
    overrides: [propertyRepositoryProvider.overrideWithValue(_FakeRepo(items))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: const Scaffold(body: PortfolioYieldSection()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — computePortfolioYield (calcul pur)
// ---------------------------------------------------------------------------

void main() {
  group('computePortfolioYield', () {
    test(
      'bien avec prix d\'achat + bail actif → rendements et cash flow calculés',
      () {
        final items = [
          _makeItem(
            id: 'p1',
            purchasePriceCents: 20000000, // 200k€
            activeLeaseId: 'lease-1',
            rentHcCents: 80000, // 800€/mois → 9600€/an
            propertyTaxAnnualCents: 120000, // 1200€/an
            insurancePnoAnnualCents: 30000, // 300€/an
            condoFeesNonRecoverableCents: 60000, // 600€/an
          ),
        ];

        final summary = computePortfolioYield(items);

        expect(summary.computedCount, 1);
        expect(summary.totalCount, 1);
        // (9600 - 2100) / 200000 * 100 = 3.75% net ; brut = 9600/200000*100 = 4.8%
        expect(summary.avgYieldGrossPercent, closeTo(4.8, 0.01));
        expect(summary.avgYieldNetPercent, closeTo(3.75, 0.01));
      },
    );

    test('bien sans prix d\'achat → exclu du calcul', () {
      final items = [
        _makeItem(
          id: 'p-no-price',
          activeLeaseId: 'lease-1',
          rentHcCents: 80000,
        ),
        _makeItem(
          id: 'p-with-price',
          purchasePriceCents: 20000000,
          activeLeaseId: 'lease-2',
          rentHcCents: 80000,
        ),
      ];

      final summary = computePortfolioYield(items);

      expect(summary.computedCount, 1);
      expect(summary.totalCount, 2);
      // Seul p-with-price contribue — sinon la moyenne serait faussée.
      expect(summary.avgYieldGrossPercent, closeTo(4.8, 0.01));
    });

    test('bien sans bail actif (vacant) → exclu du calcul', () {
      final items = [
        _makeItem(id: 'p-vacant', purchasePriceCents: 20000000),
        _makeItem(
          id: 'p-occupied',
          purchasePriceCents: 30000000,
          activeLeaseId: 'lease-1',
          rentHcCents: 100000, // 1000€/mois → 4% brut
        ),
      ];

      final summary = computePortfolioYield(items);

      expect(summary.computedCount, 1);
      expect(summary.totalCount, 2);
      expect(summary.avgYieldGrossPercent, closeTo(4.0, 0.01));
    });

    test(
      'portefeuille entièrement non calculable → tout est null (pas 0,00 %)',
      () {
        final items = [
          _makeItem(
            id: 'p-no-price',
            activeLeaseId: 'lease-1',
            rentHcCents: 80000,
          ),
          _makeItem(id: 'p-vacant', purchasePriceCents: 20000000),
        ];

        final summary = computePortfolioYield(items);

        expect(summary.computedCount, 0);
        expect(summary.totalCount, 2);
        expect(summary.avgYieldGrossPercent, isNull);
        expect(summary.avgYieldNetPercent, isNull);
      },
    );

    test('pondération par prix d\'achat sur 2 biens de prix différents', () {
      final items = [
        _makeItem(
          id: 'p-small',
          purchasePriceCents: 10000000, // 100k€
          activeLeaseId: 'lease-1',
          rentHcCents: 50000, // 500€/mois → 6% brut
          propertyTaxAnnualCents: 24000, // 240€/an → net 5.76%
        ),
        _makeItem(
          id: 'p-big',
          purchasePriceCents: 30000000, // 300k€
          activeLeaseId: 'lease-2',
          rentHcCents: 100000, // 1000€/mois → 4% brut
          propertyTaxAnnualCents: 48000, // 480€/an → net 3.84%
        ),
      ];

      final summary = computePortfolioYield(items);

      expect(summary.computedCount, 2);
      // Moyenne simple (6 + 4) / 2 = 5% — la pondération par prix doit s'en
      // écarter : (6×100k + 4×300k) / 400k = 4.5%.
      expect(summary.avgYieldGrossPercent, isNot(closeTo(5.0, 0.001)));
      expect(summary.avgYieldGrossPercent, closeTo(4.5, 0.01));
      // Même pondération appliquée au net : (5.76×100k + 3.84×300k)/400k = 4.32%.
      expect(summary.avgYieldNetPercent, closeTo(4.32, 0.01));
    });

    test('portfolio vide → computedCount et totalCount à 0, rien à null', () {
      final summary = computePortfolioYield(const []);

      expect(summary.computedCount, 0);
      expect(summary.totalCount, 0);
      expect(summary.avgYieldGrossPercent, isNull);
      expect(summary.avgYieldNetPercent, isNull);
    });
  });

  group('yieldTierFor — paliers de couleur', () {
    test('null → none (pas de palier)', () {
      expect(yieldTierFor(null), YieldTier.none);
    });
    test('négatif → negative', () {
      expect(yieldTierFor(-0.01), YieldTier.negative);
      expect(yieldTierFor(-5), YieldTier.negative);
    });
    test('positif et < 10 % → low (0 inclus)', () {
      expect(yieldTierFor(0), YieldTier.low);
      expect(yieldTierFor(5), YieldTier.low);
      expect(yieldTierFor(9.99), YieldTier.low);
    });
    test('≥ 10 % → good (borne incluse)', () {
      expect(yieldTierFor(10), YieldTier.good);
      expect(yieldTierFor(15.5), YieldTier.good);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — PortfolioYieldSection (widget)
  // ---------------------------------------------------------------------------

  group('PortfolioYieldSection — widget', () {
    testWidgets('portfolio non calculable → message explicite, pas 0,00 %', (
      tester,
    ) async {
      final items = [_makeItem(id: 'p-vacant', purchasePriceCents: 20000000)];

      await tester.pumpWidget(_wrap(items));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Saisir le prix d'achat et créer un bail sur vos biens pour "
          'afficher la rentabilité portfolio.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('0,00 %'), findsNothing);
      expect(find.byKey(const Key('kpi_portfolio_gross_yield')), findsNothing);
    });

    testWidgets('portfolio calculable → affiche le rendement réel', (
      tester,
    ) async {
      final items = [
        _makeItem(
          id: 'p1',
          purchasePriceCents: 20000000,
          activeLeaseId: 'lease-1',
          rentHcCents: 80000,
        ),
      ];

      await tester.pumpWidget(_wrap(items));
      await tester.pumpAndSettle();

      // Formaté via toStringAsFixed (non localisé) — cf. _PortfolioKpiCard.
      expect(find.text('4.80 %'), findsOneWidget);
      expect(find.textContaining('1 bien'), findsOneWidget);
      // Verrou de régression : la carte cash-flow a été retirée (dédup avec
      // le graphe mensuel) — un re-ajout silencieux doit être détecté ici.
      expect(find.byKey(const Key('kpi_portfolio_cashflow')), findsNothing);
    });
  });
}

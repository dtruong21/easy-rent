/// Tests widget de [PropertyProfitabilityCard] — focus sur la transparence
/// réel/prévisionnel du cash flow affiché (FEAT cash flow réel) : l'écran
/// doit toujours indiquer, en une phrase, si le chiffre vient du réel ou
/// du prévisionnel.
library;

import 'package:easyrent/core/finance/real_expense_charges.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/properties/application/active_lease_provider.dart';
import 'package:easyrent/features/properties/application/property_real_charges_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_profitability_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  const _FakeRepo(this.property);

  final Property property;

  @override
  Future<Property> getById(String id) async => property;

  @override
  Future<List<Property>> list() async => [property];

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

  @override
  Future<List<PropertyListItem>> listWithLeases() async =>
      [property].map((p) => PropertyListItem(property: p)).toList();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty() => Property(
  id: 'prop-1',
  landlordId: 'owner-1',
  name: 'Appart Test',
  address: '1 rue Test, 75001 Paris',
  type: PropertyType.appartement,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
  purchasePriceCents: 20000000, // 200k€
  propertyTaxAnnualCents: 120000, // 1200€/an déclaré
  insurancePnoAnnualCents: 30000, // 300€/an déclaré
  condoFeesNonRecoverableCents: 60000, // 600€/an déclaré
);

Widget _wrap({
  required Property property,
  required int? monthlyRentHcCents,
  required PropertyRealCharges realCharges,
}) {
  return ProviderScope(
    overrides: [
      propertyRepositoryProvider.overrideWithValue(_FakeRepo(property)),
      activeLeaseRentProvider.overrideWith(
        (ref, id) async => monthlyRentHcCents,
      ),
      propertyRealChargesProvider.overrideWith((ref, id) async => realCharges),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: PropertyProfitabilityCard(propertyId: property.id)),
    ),
  );
}

void main() {
  group('PropertyProfitabilityCard — transparence réel/prévisionnel', () {
    testWidgets(
      'aucune dépense réelle exploitable → pas de mention "dépenses réelles"',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            property: _makeProperty(),
            monthlyRentHcCents: 80000,
            realCharges: PropertyRealCharges.empty,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('dépenses réelles'), findsNothing);
        // Le disclaimer prévisionnel générique reste affiché.
        expect(
          find.textContaining('Estimation indicative avant impôt'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '1 charge sur 3 basculée sur le réel → message explicite au singulier',
      (tester) async {
        final now = DateTime.now();
        final realCharges = PropertyRealCharges(
          propertyTax: [
            // Ancre hors fenêtre (≥ 1 an) → couverture acquise.
            RealChargeEntry(
              amountCents: 50000,
              expenseDate: now.subtract(const Duration(days: 400)),
            ),
            // Dans la fenêtre glissante → utilisée pour la moyenne.
            RealChargeEntry(
              amountCents: 240000,
              expenseDate: now.subtract(const Duration(days: 60)),
            ),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            property: _makeProperty(),
            monthlyRentHcCents: 80000,
            realCharges: realCharges,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Basé sur vos dépenses réelles pour 1 charge sur 3 '
            '(moyenne lissée sur 12 mois).',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dépense isolée récente (sans recul) → aucune bascule, message absent',
      (tester) async {
        final now = DateTime.now();
        final realCharges = PropertyRealCharges(
          propertyTax: [
            RealChargeEntry(
              amountCents: 5000, // 50€, aucun recul → repli sur le déclaré
              expenseDate: now.subtract(const Duration(days: 10)),
            ),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            property: _makeProperty(),
            monthlyRentHcCents: 80000,
            realCharges: realCharges,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('dépenses réelles'), findsNothing);
      },
    );
  });
}

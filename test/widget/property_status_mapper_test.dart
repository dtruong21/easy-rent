import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_status_mapper.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty({String id = 'p1'}) => Property(
  id: id,
  landlordId: 'owner',
  name: 'Appartement Test',
  address: '1 rue Test, 75001 Paris',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

PropertyListItem _makeItem({
  String? activeLeaseId,
  String? tenantName,
  String? rentLabel,
}) => PropertyListItem(
  property: _makeProperty(),
  activeLeaseId: activeLeaseId,
  currentTenantName: tenantName,
  currentRentLabel: rentLabel,
);

/// Capture le résultat de [propertyOccupancyPill] depuis un [BuildContext]
/// localisé (FEAT-043 — la fonction nécessite désormais un [BuildContext]
/// pour résoudre les libellés via `AppLocalizations`).
PropertyOccupancyPillData? _captured;

Widget _harness(PropertyListItem item) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Builder(
    builder: (context) {
      _captured = propertyOccupancyPill(item, context);
      return const SizedBox.shrink();
    },
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('propertyOccupancyPill', () {
    testWidgets('bail actif → success "Loué"', (tester) async {
      final item = _makeItem(
        activeLeaseId: 'l1',
        tenantName: 'Jean Dupont',
        rentLabel: '1 200,00 € CC / mois',
      );

      await tester.pumpWidget(_harness(item));
      final result = _captured!;

      expect(result.label, 'Loué');
      expect(result.tone.name, 'success');
      expect(result.icon, Icons.home_filled);
    });

    testWidgets('pas de bail → warning "Vacant"', (tester) async {
      final item = _makeItem();

      await tester.pumpWidget(_harness(item));
      final result = _captured!;

      expect(result.label, 'Vacant');
      expect(result.tone.name, 'warning');
      expect(result.icon, Icons.home_work_outlined);
    });

    testWidgets('bail actif sans loyer → success "Loué" (loyer null toléré)', (
      tester,
    ) async {
      final item = _makeItem(
        activeLeaseId: 'l2',
        tenantName: 'Marie Martin',
        // rentLabel null — champ optionnel
      );

      await tester.pumpWidget(_harness(item));
      final result = _captured!;

      expect(result.label, 'Loué');
      expect(result.tone.name, 'success');
    });

    testWidgets(
      'bail actif sans locataire → success "Loué" (tenant null toléré)',
      (tester) async {
        final item = _makeItem(
          activeLeaseId: 'l3',
          // tenantName null — champ optionnel
          rentLabel: '800,00 € CC / mois',
        );

        await tester.pumpWidget(_harness(item));
        final result = _captured!;

        expect(result.label, 'Loué');
        expect(result.tone.name, 'success');
      },
    );
  });
}

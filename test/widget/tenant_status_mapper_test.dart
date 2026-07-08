import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_status_mapper.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Tenant _makeTenant({String id = 't1'}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _makeItem({String? activeLeaseId}) => TenantListItem(
  tenant: _makeTenant(),
  activeLeaseId: activeLeaseId,
  currentPropertyName: activeLeaseId != null ? 'Appartement Test' : null,
  activeLeasePeriodLabel: activeLeaseId != null ? 'Depuis 01/01/2024' : null,
  activeLeaseRentCents: activeLeaseId != null ? 80000 : null,
);

/// Capture le résultat de [tenantOccupancyPill] depuis un [BuildContext]
/// localisé (FEAT-043 — la fonction nécessite désormais un [BuildContext]
/// pour résoudre les libellés via `AppLocalizations`).
TenantOccupancyPillData? _captured;

Widget _harness(TenantListItem item) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Builder(
    builder: (context) {
      _captured = tenantOccupancyPill(context, item);
      return const SizedBox.shrink();
    },
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('tenantOccupancyPill', () {
    testWidgets('locataire avec bail actif → tone success, label "Actif"', (
      tester,
    ) async {
      final item = _makeItem(activeLeaseId: 'lease-123');
      await tester.pumpWidget(_harness(item));
      final pill = _captured!;

      expect(pill.tone, StatusPillTone.success);
      expect(pill.label, 'Actif');
      expect(pill.icon, isA<IconData>());
    });

    testWidgets('locataire sans bail → tone warning, label "Sans bail"', (
      tester,
    ) async {
      final item = _makeItem();
      await tester.pumpWidget(_harness(item));
      final pill = _captured!;

      expect(pill.tone, StatusPillTone.warning);
      expect(pill.label, 'Sans bail');
      expect(pill.icon, isA<IconData>());
    });

    testWidgets('locataire avec bail actif → icône différente de sans bail', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_makeItem(activeLeaseId: 'l1')));
      final withLease = _captured!;

      await tester.pumpWidget(_harness(_makeItem()));
      final withoutLease = _captured!;

      expect(withLease.icon, isNot(equals(withoutLease.icon)));
    });
  });
}

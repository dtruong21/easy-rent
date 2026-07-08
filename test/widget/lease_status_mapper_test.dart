import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/widgets/lease_status_mapper.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
}) => Lease(
  id: 'l1',
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  endDate: endDate,
  status: status,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// Date fictive "aujourd'hui" pour les tests.
final _now = DateTime(2026, 6, 22);

/// Capture le résultat de [leaseStatusPill] depuis un [BuildContext]
/// localisé (FEAT-043 — la fonction nécessite désormais un [BuildContext]
/// pour résoudre les libellés via `AppLocalizations`).
LeaseStatusPillData? _captured;

Widget _harness(Lease lease, {DateTime? now, bool isLate = false}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: Builder(
        builder: (context) {
          _captured = leaseStatusPill(context, lease, now: now, isLate: isLate);
          return const SizedBox.shrink();
        },
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('leaseStatusPill', () {
    testWidgets('active, endDate=null → success "Actif"', (tester) async {
      await tester.pumpWidget(_harness(_makeLease(), now: _now));
      final result = _captured!;

      expect(result.label, 'Actif');
      expect(result.tone.name, 'success');
      expect(result.icon, Icons.check_circle_outline);
    });

    testWidgets('active, endDate=today+90j → success "Actif"', (tester) async {
      await tester.pumpWidget(
        _harness(
          _makeLease(endDate: _now.add(const Duration(days: 90))),
          now: _now,
        ),
      );
      final result = _captured!;

      expect(result.label, 'Actif');
      expect(result.tone.name, 'success');
    });

    testWidgets('active, endDate=today+59j → warning "À renouveler"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _makeLease(endDate: _now.add(const Duration(days: 59))),
          now: _now,
        ),
      );
      final result = _captured!;

      expect(result.label, 'À renouveler');
      expect(result.tone.name, 'warning');
      expect(result.icon, Icons.event_repeat_outlined);
    });

    testWidgets(
      'active, endDate=today-10j → success (échu mais actif — pas de retard Phase 1)',
      (tester) async {
        // Un bail dont la date de fin est passée mais status toujours active
        // (données incohérentes ou bail en cours de clôture) reste "Actif" en Phase 1.
        await tester.pumpWidget(
          _harness(
            _makeLease(endDate: _now.subtract(const Duration(days: 10))),
            now: _now,
          ),
        );
        final result = _captured!;

        // endDate - today = -10 jours → inDays < 60 → warning "À renouveler"
        // (car la condition is < 60, et -10 < 60 est vrai)
        expect(result.label, 'À renouveler');
        expect(result.tone.name, 'warning');
      },
    );

    testWidgets('terminated → neutral "Terminé"', (tester) async {
      await tester.pumpWidget(
        _harness(_makeLease(status: LeaseStatus.terminated), now: _now),
      );
      final result = _captured!;

      expect(result.label, 'Terminé');
      expect(result.tone.name, 'neutral');
      expect(result.icon, Icons.lock_outline);
    });

    testWidgets('archived → neutral "Archivé"', (tester) async {
      await tester.pumpWidget(
        _harness(_makeLease(status: LeaseStatus.archived), now: _now),
      );
      final result = _captured!;

      expect(result.label, 'Archivé');
      expect(result.tone.name, 'neutral');
      expect(result.icon, Icons.archive_outlined);
    });

    // -------------------------------------------------------------------
    // FEAT-028 : priorité `late` (danger "En retard")
    // -------------------------------------------------------------------

    testWidgets('active, isLate=true, endDate=null → danger "En retard"', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_makeLease(), now: _now, isLate: true));
      final result = _captured!;

      expect(result.label, 'En retard');
      expect(result.tone.name, 'danger');
      expect(result.icon, Icons.warning_amber_outlined);
    });

    testWidgets('active, isLate=true ET endDate proche (<60j, renouvelable) → '
        '"En retard" prime sur "À renouveler" (priorité late > renewable)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _makeLease(endDate: _now.add(const Duration(days: 30))),
          now: _now,
          isLate: true,
        ),
      );
      final result = _captured!;

      expect(result.label, 'En retard');
      expect(result.tone.name, 'danger');
    });

    testWidgets(
      'active, isLate=false (défaut) → comportement inchangé "Actif"',
      (tester) async {
        await tester.pumpWidget(_harness(_makeLease(), now: _now));
        final result = _captured!;

        expect(result.label, 'Actif');
        expect(result.tone.name, 'success');
      },
    );

    testWidgets('terminated, isLate=true → reste "Terminé" (isLate ignoré hors '
        'status active)', (tester) async {
      await tester.pumpWidget(
        _harness(
          _makeLease(status: LeaseStatus.terminated),
          now: _now,
          isLate: true,
        ),
      );
      final result = _captured!;

      expect(result.label, 'Terminé');
      expect(result.tone.name, 'neutral');
    });
  });
}

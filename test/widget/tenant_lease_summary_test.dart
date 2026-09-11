import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/payments/application/lease_payments_provider.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_lease_summary.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildWidget(List<Map<String, dynamic>> leases) {
  return ProviderScope(
    overrides: [
      leasePaymentsProvider.overrideWith(() => _FakePayments(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: TenantLeaseSummary(leases: leases)),
    ),
  );
}

class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._payments);
  final List<Payment> _payments;
  @override
  Future<List<Payment>> build(String arg) async => _payments;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantLeaseSummary', () {
    // -----------------------------------------------------------------------
    // État vide
    // -----------------------------------------------------------------------
    testWidgets('liste vide — affiche "Aucun bail enregistré"', (tester) async {
      await tester.pumpWidget(_buildWidget([]));

      expect(find.textContaining('Aucun bail enregistré'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Badge statut
    // -----------------------------------------------------------------------
    testWidgets('statut "active" → badge "Actif"', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('statut "terminated" → badge "Terminé"', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2023-01-01',
            'end_date': '2024-01-01',
            'status': 'terminated',
            'rent_amount_cents': 65000,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.text('Terminé'), findsOneWidget);
    });

    testWidgets('statut "archived" → badge "Archivé"', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2022-01-01',
            'end_date': '2023-01-01',
            'status': 'archived',
            'rent_amount_cents': 60000,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.text('Archivé'), findsOneWidget);
    });

    testWidgets(
      'statut inconnu → fallback "Archivé" (comportement défensif de LeaseStatus.fromSql)',
      (tester) async {
        await tester.pumpWidget(
          _buildWidget([
            {
              'id': 'l1',
              'property_id': 'p1',
              'start_date': '2024-01-01',
              'end_date': null,
              'status': 'pending',
              'rent_amount_cents': 70000,
              'payment_day': 5,
            },
          ]),
        );

        // LeaseStatus.fromSql('pending') → archived (fallback défensif).
        expect(find.text('Archivé'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Formatage dates (DD/MM/YYYY)
    // -----------------------------------------------------------------------
    testWidgets('bail sans end_date — affiche "(CDI)"', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-06-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
            'payment_day': 5,
          },
        ]),
      );

      // Format attendu : "Du 01/06/2024 (CDI)"
      expect(find.textContaining('01/06/2024'), findsOneWidget);
      expect(find.textContaining('CDI'), findsOneWidget);
    });

    testWidgets('bail avec end_date — affiche la période complète', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2023-03-15',
            'end_date': '2024-03-14',
            'status': 'terminated',
            'rent_amount_cents': 65000,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.textContaining('15/03/2023'), findsOneWidget);
      expect(find.textContaining('14/03/2024'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Montant en € (formatage FR : virgule décimale)
    //
    // MoneyFormat.formatEurosFromCents utilise intl fr_FR.
    // Le suffixe "/mois HC" suit directement la valeur formatée.
    // Les assertions vérifient la valeur numérique et le suffixe séparément,
    // pour être robustes au séparateur variable (espace fine insécable vs espace)
    // utilisé par intl entre le montant et le symbole €.
    // -----------------------------------------------------------------------
    testWidgets('montant formaté en € avec virgule (800,00 €/mois HC)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
            'payment_day': 5,
          },
        ]),
      );

      // 80000 centimes = 800,00 €
      expect(find.textContaining('800,00'), findsOneWidget);
      expect(find.textContaining('€/mois HC'), findsOneWidget);
    });

    testWidgets(
      'montant fractionnaire formaté correctement (750,50 €/mois HC)',
      (tester) async {
        await tester.pumpWidget(
          _buildWidget([
            {
              'id': 'l1',
              'property_id': 'p1',
              'start_date': '2024-01-01',
              'end_date': null,
              'status': 'active',
              'rent_amount_cents': 75050,
              'payment_day': 5,
            },
          ]),
        );

        // 75050 centimes = 750,50 €
        expect(find.textContaining('750,50'), findsOneWidget);
        expect(find.textContaining('€/mois HC'), findsOneWidget);
      },
    );

    testWidgets('montant 0 centimes → "0,00 €/mois HC"', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 0,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.textContaining('0,00'), findsWidgets);
      expect(find.textContaining('€/mois HC'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Plusieurs baux
    // -----------------------------------------------------------------------
    testWidgets('plusieurs baux — affiche tous les badges', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
            'payment_day': 5,
          },
          {
            'id': 'l2',
            'property_id': 'p2',
            'start_date': '2022-01-01',
            'end_date': '2023-12-31',
            'status': 'terminated',
            'rent_amount_cents': 65000,
            'payment_day': 5,
          },
        ]),
      );

      expect(find.text('Actif'), findsOneWidget);
      expect(find.text('Terminé'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Champs manquants (robustesse)
    // -----------------------------------------------------------------------
    testWidgets('rent_amount_cents manquant → traité comme 0', (tester) async {
      await tester.pumpWidget(
        _buildWidget([
          {
            'id': 'l1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            // pas de rent_amount_cents
            'payment_day': 5,
          },
        ]),
      );

      expect(find.textContaining('0,00'), findsWidgets);
      expect(find.textContaining('€/mois HC'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Ponctualité par bail (#175, Task 5)
    // -----------------------------------------------------------------------
    testWidgets('ligne de bail porte l\'indicateur de ponctualité si payment_day', (
      tester,
    ) async {
      final payments = [
        Payment(
          id: 'p1',
          leaseId: 'lz',
          landlordId: 'lord1',
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          paidAt: DateTime(2026, 1, 8), // échéance 5 + 5j = 10 → à l'heure
          rentAmountCents: 80000,
          chargesAmountCents: 0,
          paymentMethod: PaymentMethod.virement,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leasePaymentsProvider.overrideWith(() => _FakePayments(payments)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
            home: const Scaffold(
              body: TenantLeaseSummary(
                leases: [
                  {
                    'id': 'lz',
                    'status': 'active',
                    'start_date': '2026-01-01T00:00:00.000Z',
                    'end_date': null,
                    'rent_amount_cents': 80000,
                    'payment_day': 5,
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_punctuality_tap')), findsOneWidget);
    });
  });
}

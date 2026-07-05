import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_lease_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildWidget(List<Map<String, dynamic>> leases) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: TenantLeaseSummary(leases: leases)),
  );
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
          },
          {
            'id': 'l2',
            'property_id': 'p2',
            'start_date': '2022-01-01',
            'end_date': '2023-12-31',
            'status': 'terminated',
            'rent_amount_cents': 65000,
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
          },
        ]),
      );

      expect(find.textContaining('0,00'), findsWidgets);
      expect(find.textContaining('€/mois HC'), findsOneWidget);
    });
  });
}

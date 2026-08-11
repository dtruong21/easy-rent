/// Tests de [PropertyLeaseSummary] — section "Baux actifs" de la fiche bien
/// (FEAT-005, remplace le stub `propertiesDetailActiveLeasesStub`).
///
/// Même patron que `tenant_lease_summary_test.dart` /
/// `tenant_lease_summary_nav_test.dart` : liste de Map brute snake_case,
/// état vide, badge de statut, formatage période/montant, navigation
/// `context.push('/leases/:id')`.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_lease_summary.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers de montage
// ---------------------------------------------------------------------------

Widget _buildWidget(List<Map<String, dynamic>> leases) {
  return MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
    home: Scaffold(body: PropertyLeaseSummary(leases: leases)),
  );
}

Widget _buildWithRouter(List<Map<String, dynamic>> leases) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: PropertyLeaseSummary(leases: leases)),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('bail ${state.pathParameters['id']}')),
      ),
    ],
  );

  return MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertyLeaseSummary', () {
    // -----------------------------------------------------------------------
    // État vide
    // -----------------------------------------------------------------------
    testWidgets('liste vide — affiche "Aucun bail actif pour ce bien."', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWidget(const []));

      expect(find.text('Aucun bail actif pour ce bien.'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Affichage d'un bail actif
    // -----------------------------------------------------------------------
    testWidgets('un bail actif — badge "Actif", période et loyer formatés', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(const [
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

      expect(find.text('Actif'), findsOneWidget);
      // Format attendu : "Du 01/06/2024 (CDI)"
      expect(find.textContaining('01/06/2024'), findsOneWidget);
      expect(find.textContaining('CDI'), findsOneWidget);
      expect(find.textContaining('800,00'), findsOneWidget);
      expect(find.textContaining('€/mois HC'), findsOneWidget);
    });

    testWidgets('plusieurs baux actifs — affiche chaque entrée', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(const [
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
            'property_id': 'p1',
            'start_date': '2023-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 65000,
          },
        ]),
      );

      expect(find.text('Actif'), findsNWidgets(2));
      expect(find.text('Voir le bail'), findsNWidgets(2));
    });

    // -----------------------------------------------------------------------
    // Navigation — tap vers /leases/:id (context.push, empile la pile)
    // -----------------------------------------------------------------------
    testWidgets('tap sur un bail navigue vers /leases/:id', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter(const [
          {
            'id': 'lease-nav-1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voir le bail'));
      await tester.pumpAndSettle();

      expect(find.text('bail lease-nav-1'), findsOneWidget);
    });

    testWidgets('bail avec id vide — pas de lien "Voir le bail"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter(const [
          {
            'id': '',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voir le bail'), findsNothing);
    });
  });
}

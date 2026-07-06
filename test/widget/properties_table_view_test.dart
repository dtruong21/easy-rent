import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/properties_table_view.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Property _makeProperty({
  String id = 'p1',
  String name = 'Appartement Test',
  PropertyType type = PropertyType.appartement,
  double? surfaceM2,
}) => Property(
  id: id,
  landlordId: 'owner',
  name: name,
  address: '1 rue Test, 75001 Paris',
  type: type,
  surfaceM2: surfaceM2,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

PropertyListItem _makeItem({
  String id = 'p1',
  String name = 'Appartement Test',
  String? activeLeaseId,
  String? tenantName,
  double? surfaceM2,
  PropertyType type = PropertyType.appartement,
}) => PropertyListItem(
  property: _makeProperty(id: id, name: name, type: type, surfaceM2: surfaceM2),
  activeLeaseId: activeLeaseId,
  currentTenantName: tenantName,
  currentRentLabel: activeLeaseId != null ? '1 200,00 € CC / mois' : null,
);

Widget _buildTableView(List<PropertyListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: PropertiesTableView(properties: items)),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, _) => const Scaffold(body: Text('new lease')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: _appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertiesTableView', () {
    testWidgets('N lignes — affiche N DataRow', (tester) async {
      final items = [
        _makeItem(id: 'p1', name: 'Bien A'),
        _makeItem(id: 'p2', name: 'Bien B'),
        _makeItem(id: 'p3', name: 'Bien C'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.text('Bien A'), findsOneWidget);
      expect(find.text('Bien B'), findsOneWidget);
      expect(find.text('Bien C'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('tri — les deux éléments visibles après clic sur en-tête', (
      tester,
    ) async {
      final items = [
        _makeItem(id: 'p1', name: 'Zebra'),
        _makeItem(id: 'p2', name: 'Alpha'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.text('Zebra'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);

      // Clic sur l'en-tête "Bien" → déclenche tri
      await tester.tap(find.text('Bien'));
      await tester.pumpAndSettle();

      expect(find.text('Zebra'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('tap ligne → navigue vers /properties/:id', (tester) async {
      final items = [_makeItem(id: 'prop-tbl', name: 'Bien Nav')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bien Nav'));
      await tester.pumpAndSettle();

      expect(find.text('detail prop-tbl'), findsOneWidget);
    });

    testWidgets('bien loué — icône "Voir le bail" présente', (tester) async {
      final items = [_makeItem(id: 'pa', activeLeaseId: 'l1')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table_lease_pa')), findsOneWidget);
      expect(find.byKey(const Key('table_new_lease_pa')), findsNothing);
    });

    testWidgets('bien vacant — icône "Créer un bail" présente', (tester) async {
      final items = [_makeItem(id: 'pv')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table_new_lease_pv')), findsOneWidget);
      expect(find.byKey(const Key('table_lease_pv')), findsNothing);
    });

    testWidgets('état loading — affiche aucun DataTable de données', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) =>
                Scaffold(body: PropertiesTableView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: _appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DataTable), findsNothing);
    });
  });
}

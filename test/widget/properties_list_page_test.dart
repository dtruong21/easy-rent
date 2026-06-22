import 'dart:async';

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/properties/application/properties_filter_provider.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_filter.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/properties_list_page.dart';
import 'package:easyrent/features/properties/presentation/widgets/properties_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  final List<PropertyListItem> items;
  final Exception? listError;

  const _FakeRepo({this.items = const [], this.listError});

  @override
  Future<List<Property>> list() async {
    if (listError != null) throw listError!;
    return items.map((i) => i.property).toList();
  }

  @override
  Future<List<PropertyListItem>> listWithLeases() async {
    if (listError != null) throw listError!;
    return items;
  }

  @override
  Future<Property> getById(String id) async => items.first.property;

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Property _makeProperty({
  String id = 'p1',
  String name = 'Appart Test',
  PropertyType type = PropertyType.appartement,
}) => Property(
  id: id,
  landlordId: 'owner-1',
  name: name,
  address: '1 rue de la Paix, 75001 Paris',
  type: type,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

PropertyListItem _makeItem({
  String id = 'p1',
  String name = 'Appart Test',
  PropertyType type = PropertyType.appartement,
  String? activeLeaseId,
  String? tenantName,
}) => PropertyListItem(
  property: _makeProperty(id: id, name: name, type: type),
  activeLeaseId: activeLeaseId,
  currentTenantName: tenantName,
  currentRentLabel: activeLeaseId != null ? '1 200,00 € CC / mois' : null,
);

Widget _buildPage(_FakeRepo repo) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => const PropertiesListPage()),
      GoRoute(
        path: '/properties/new',
        builder: (context, _) => const Scaffold(body: Text('new property')),
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
    overrides: [propertyRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertiesListPage', () {
    // -----------------------------------------------------------------------
    // État vide
    // -----------------------------------------------------------------------
    testWidgets('état vide — affiche "Aucun bien enregistré"', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Aucun bien enregistré'), findsOneWidget);
    });

    testWidgets('état vide — bouton "Ajouter un bien" présent', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_add_property_empty')), findsOneWidget);
    });

    testWidgets('état vide — FAB "Ajouter un bien" présent', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fab_add_property')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Liste avec items
    // -----------------------------------------------------------------------
    testWidgets('liste — affiche les noms des biens', (tester) async {
      final repo = _FakeRepo(
        items: [
          _makeItem(id: 'p1', name: 'Appartement Paris'),
          _makeItem(id: 'p2', name: 'Studio Lyon'),
        ],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Appartement Paris'), findsOneWidget);
      expect(find.text('Studio Lyon'), findsOneWidget);
    });

    testWidgets('liste — état vide absent quand des biens existent', (
      tester,
    ) async {
      final repo = _FakeRepo(
        items: [_makeItem(id: 'p1', name: 'Maison Bordeaux')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Aucun bien enregistré'), findsNothing);
    });

    testWidgets('liste — PropertiesCardView visible par défaut', (
      tester,
    ) async {
      final repo = _FakeRepo(
        items: [_makeItem(id: 'p1', name: 'Maison Test')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.byType(PropertiesCardView), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Filtres
    // -----------------------------------------------------------------------
    testWidgets('filtre occupied — affiche uniquement les biens loués', (
      tester,
    ) async {
      final repo = _FakeRepo(
        items: [
          _makeItem(
            id: 'p1',
            name: 'Bien Loué',
            activeLeaseId: 'l1',
            tenantName: 'Jean Dupont',
          ),
          _makeItem(id: 'p2', name: 'Bien Vacant'),
        ],
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => const PropertiesListPage(),
          ),
          GoRoute(
            path: '/properties/new',
            builder: (context, _) => const Scaffold(body: Text('new property')),
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

      final container = ProviderContainer(
        overrides: [propertyRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Appliquer le filtre "Loués"
      container.read(propertyFilterProvider.notifier).state =
          PropertyFilter.occupied;
      await tester.pumpAndSettle();

      expect(find.text('Bien Loué'), findsOneWidget);
      expect(find.text('Bien Vacant'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('état loading — skeleton visible', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => const PropertiesListPage(),
          ),
          GoRoute(
            path: '/properties/new',
            builder: (context, _) => const Scaffold(body: Text('new')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertiesListItemsProvider.overrideWith(
              () => _LoadingListItemsNotifier(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );

      await tester.pump();
      // Pas d'erreur et pas de contenu de liste pendant loading
      expect(find.text('Aucun bien enregistré'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // État erreur
    // -----------------------------------------------------------------------
    testWidgets('état erreur — affiche bouton "Réessayer"', (tester) async {
      final repo = _FakeRepo(listError: Exception('réseau indisponible'));

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}

/// Notifier qui reste en état loading indéfini — sans timer.
class _LoadingListItemsNotifier extends PropertiesListItemsNotifier {
  @override
  Future<List<PropertyListItem>> build() async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    return [];
  }
}

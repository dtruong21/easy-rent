import 'dart:async';

import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/properties_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  final List<Property> properties;
  final Exception? listError;

  const _FakeRepo({this.properties = const [], this.listError});

  @override
  Future<List<Property>> list() async {
    if (listError != null) throw listError!;
    return properties;
  }

  @override
  Future<Property> getById(String id) async => properties.first;

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
    ],
  );

  return ProviderScope(
    overrides: [propertyRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
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

      expect(find.text('Démarrez votre parc locatif'), findsOneWidget);
    });

    testWidgets('état vide — bouton "Ajouter un bien" présent', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      // Le bouton dans l'état vide a la key btn_add_property_empty.
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
        properties: [
          _makeProperty(id: 'p1', name: 'Appartement Paris'),
          _makeProperty(id: 'p2', name: 'Studio Lyon'),
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
        properties: [_makeProperty(id: 'p1', name: 'Maison Bordeaux')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Démarrez votre parc locatif'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('état loading — CircularProgressIndicator visible', (
      tester,
    ) async {
      // Override direct du provider AsyncNotifier pour rester en état loading.
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
            propertiesListProvider.overrideWith(() => _LoadingListNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      // Avant pumpAndSettle — on reste en loading.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
class _LoadingListNotifier extends PropertiesListNotifier {
  @override
  Future<List<Property>> build() async {
    // Ne complète pas — expose l'état loading initial d'AsyncNotifier.
    state = const AsyncValue.loading();
    await Completer<void>().future; // attend sans timer réel
    return [];
  }
}

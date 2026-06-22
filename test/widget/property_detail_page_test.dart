import 'dart:async';

import 'package:easyrent/features/properties/application/property_detail_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/property_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  final Property? result;
  final bool throwNotFound;
  int archiveCalls = 0;

  _FakeRepo({this.result, this.throwNotFound = false});

  @override
  Future<Property> getById(String id) async {
    if (throwNotFound) throw PropertyNotFoundException(id);
    if (result == null) throw PropertyNotFoundException(id);
    return result!;
  }

  @override
  Future<List<Property>> list() async => result == null ? [] : [result!];

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
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {
    archiveCalls++;
  }

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Property _makeProperty({double? surfaceM2}) => Property(
  id: 'prop-1',
  landlordId: 'owner-1',
  name: 'Appart Lyon',
  address: '5 rue Mercière, 69001 Lyon',
  type: PropertyType.appartement,
  surfaceM2: surfaceM2,
  createdAt: DateTime(2024, 1, 15),
  updatedAt: DateTime(2024, 3, 20),
);

Widget _buildPage({required String propertyId, required _FakeRepo repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) => PropertyDetailPage(id: propertyId),
      ),
      GoRoute(
        path: '/properties',
        builder: (context, _) => const Scaffold(body: Text('liste')),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (context, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
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
  group('PropertyDetailPage', () {
    // -----------------------------------------------------------------------
    // Bien trouvé — affichage des champs
    // -----------------------------------------------------------------------
    testWidgets('affiche le nom du bien dans l\'AppBar', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Appart Lyon'), findsWidgets);
    });

    testWidgets('affiche l\'adresse du bien', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('5 rue Mercière, 69001 Lyon'), findsOneWidget);
    });

    testWidgets('affiche le type en français', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Appartement'), findsOneWidget);
    });

    testWidgets('affiche la surface quand renseignée', (tester) async {
      final repo = _FakeRepo(result: _makeProperty(surfaceM2: 45.5));
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('45'), findsWidgets);
      expect(find.textContaining('m²'), findsWidgets);
    });

    testWidgets('n\'affiche pas la ligne surface si null', (tester) async {
      // Surface absente = la ligne "Surface" ne doit pas apparaître.
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Surface'), findsNothing);
    });

    testWidgets('bouton "Modifier" présent', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_edit_property')), findsOneWidget);
    });

    testWidgets('bouton "Archiver ce bien" présent', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_archive_property')), findsOneWidget);
    });

    testWidgets('date formatée DD/MM/YYYY — FR', (tester) async {
      // createdAt = 2024-01-15 → "15/01/2024"
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('15/01/2024'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Bien introuvable (RLS renvoie 0 ligne ou PropertyNotFoundException)
    // -----------------------------------------------------------------------
    testWidgets('cross-user / archivé — affiche "Bien introuvable"', (
      tester,
    ) async {
      final repo = _FakeRepo(throwNotFound: true);
      await tester.pumpWidget(_buildPage(propertyId: 'unknown-id', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Bien introuvable'), findsOneWidget);
    });

    testWidgets('"Bien introuvable" — bouton "Retour à la liste" présent', (
      tester,
    ) async {
      final repo = _FakeRepo(throwNotFound: true);
      await tester.pumpWidget(_buildPage(propertyId: 'x', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Retour à la liste'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('CircularProgressIndicator pendant le chargement', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => const PropertyDetailPage(id: 'prop-1'),
          ),
          GoRoute(
            path: '/properties',
            builder: (context, _) => const Scaffold(body: Text('liste')),
          ),
        ],
      );

      // Override direct du provider pour rester en état loading.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertyDetailProvider.overrideWith(() => _LoadingDetailNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

/// Notifier qui reste en état loading sans timer réel.
class _LoadingDetailNotifier extends PropertyDetailNotifier {
  @override
  Future<Property> build(String arg) async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    throw Exception('never');
  }
}

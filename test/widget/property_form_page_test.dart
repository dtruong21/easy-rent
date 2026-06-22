import 'package:easyrent/features/properties/application/property_form_controller.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_form_state.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/property_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository — aucun appel réseau.
// ---------------------------------------------------------------------------

class _FakePropertyRepository implements PropertyRepository {
  Property? createdProperty;
  Property? updatedProperty;
  Exception? createError;

  @override
  Future<List<Property>> list() async => [];

  @override
  Future<Property> getById(String id) async {
    return _makeProperty(id: id);
  }

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
  }) async {
    if (createError != null) throw createError!;
    createdProperty = _makeProperty(
      name: name,
      address: address,
      type: type,
      surfaceM2: surfaceM2,
    );
    return createdProperty!;
  }

  @override
  Future<Property> update(Property property) async {
    updatedProperty = property;
    return property;
  }

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];

  Property _makeProperty({
    String id = 'test-id',
    String name = 'Test',
    String address = '1 rue test',
    PropertyType type = PropertyType.appartement,
    double? surfaceM2,
  }) => Property(
    id: id,
    landlordId: 'landlord-id',
    name: name,
    address: address,
    type: type,
    surfaceM2: surfaceM2,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Helper de montage.
// ---------------------------------------------------------------------------

Widget _buildForm({
  Property? initial,
  _FakePropertyRepository? repo,
  PropertyFormState? initialState,
}) {
  final fakeRepo = repo ?? _FakePropertyRepository();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => PropertyFormPage(initial: initial),
      ),
      GoRoute(
        path: '/properties',
        builder: (context, state) => const Scaffold(body: Text('properties')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      propertyRepositoryProvider.overrideWithValue(fakeRepo),
      if (initialState != null)
        propertyFormControllerProvider.overrideWith(
          (ref) => PropertyFormController(ref)..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertyFormPage — smoke tests', () {
    // -----------------------------------------------------------------------
    // Mode création — champs présents
    // -----------------------------------------------------------------------
    testWidgets('mode création — les 4 champs sont présents', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_name')), findsOneWidget);
      expect(find.byKey(const Key('field_address')), findsOneWidget);
      expect(find.byKey(const Key('field_type')), findsOneWidget);
      expect(find.byKey(const Key('field_surface')), findsOneWidget);
    });

    testWidgets('mode création — titre "Nouveau bien"', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Nouveau bien'), findsOneWidget);
    });

    testWidgets('mode création — bouton "Créer le bien" présent', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Créer le bien'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Validation — erreurs inline sur soumission incomplète
    // -----------------------------------------------------------------------
    testWidgets(
      'validation — erreur "nom obligatoire" si nom vide à la soumission',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        // Effacer le nom (vide par défaut) puis taper sur Submit.
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        expect(find.text('Le nom du bien est obligatoire'), findsOneWidget);
      },
    );

    testWidgets('validation — erreur "adresse obligatoire" si adresse vide', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      // Remplir le nom mais pas l'adresse.
      await tester.enterText(find.byKey(const Key('field_name')), 'Mon appart');
      await tester.tap(find.byKey(const Key('btn_submit_form')));
      await tester.pumpAndSettle();

      expect(find.textContaining('adresse'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // Mode édition — champs pré-remplis
    // -----------------------------------------------------------------------
    testWidgets('mode édition — champs pré-remplis', (tester) async {
      final property = Property(
        id: 'id-1',
        landlordId: 'landlord-1',
        name: 'Appart Lyon',
        address: '5 rue Mercière, 69001 Lyon',
        type: PropertyType.appartement,
        surfaceM2: 42.5,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: property));
      await tester.pumpAndSettle();

      expect(find.text('Appart Lyon'), findsOneWidget);
      expect(find.text('5 rue Mercière, 69001 Lyon'), findsOneWidget);
    });

    testWidgets('mode édition — titre "Modifier le bien"', (tester) async {
      final property = Property(
        id: 'id-1',
        landlordId: 'landlord-1',
        name: 'Maison Bordeaux',
        address: '10 allée des Roses, 33000 Bordeaux',
        type: PropertyType.maison,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: property));
      await tester.pumpAndSettle();

      expect(find.text('Modifier le bien'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État submitting — bouton désactivé
    // -----------------------------------------------------------------------
    testWidgets('état submitting — bouton désactivé avec indicateur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildForm(initialState: const PropertyFormState.submitting()),
      );
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_submit_form')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État erreur — message affiché inline
    // -----------------------------------------------------------------------
    testWidgets('état erreur — message affiché inline', (tester) async {
      await tester.pumpWidget(
        _buildForm(
          initialState: const PropertyFormState.error(
            message: 'Données invalides. Vérifiez les champs et réessayez.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Données invalides'), findsOneWidget);
    });
  });
}

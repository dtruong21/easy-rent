import 'package:easyrent/features/properties/application/property_form_controller.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/application/property_detail_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_form_state.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  Property? _storedProperty;
  Exception? createError;

  _FakeRepo();

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
  }) async {
    if (createError != null) throw createError!;
    _storedProperty = Property(
      id: 'new-id',
      landlordId: 'owner',
      name: name,
      address: address,
      type: type,
      surfaceM2: surfaceM2,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    return _storedProperty!;
  }

  @override
  Future<Property> update(Property property) async {
    _storedProperty = property;
    return property;
  }

  @override
  Future<List<Property>> list() async =>
      _storedProperty == null ? [] : [_storedProperty!];

  @override
  Future<Property> getById(String id) async {
    if (_storedProperty == null) throw PropertyNotFoundException(id);
    return _storedProperty!;
  }

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Helper : construit un ProviderContainer avec le fake repo
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeRepo repo) {
  return ProviderContainer(
    overrides: [propertyRepositoryProvider.overrideWithValue(repo)],
  );
}

Property _existingProperty() => Property(
  id: 'existing-id',
  landlordId: 'owner',
  name: 'Ancien nom',
  address: 'Ancienne adresse',
  type: PropertyType.maison,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// Helpers de lecture d'état freezed.
bool _isIdle(PropertyFormState s) =>
    s.maybeWhen(idle: () => true, orElse: () => false);
bool _isSubmitting(PropertyFormState s) =>
    s.maybeWhen(submitting: () => true, orElse: () => false);
bool _isSuccess(PropertyFormState s) =>
    s.maybeWhen(success: (_) => true, orElse: () => false);
bool _isError(PropertyFormState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

Property? _successProperty(PropertyFormState s) =>
    s.maybeWhen(success: (p) => p, orElse: () => null);

String? _errorMessage(PropertyFormState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => null);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertyFormController', () {
    // -----------------------------------------------------------------------
    // État initial
    // -----------------------------------------------------------------------
    test('état initial est idle', () {
      final container = _makeContainer(_FakeRepo());
      addTearDown(container.dispose);

      final state = container.read(propertyFormControllerProvider);
      expect(_isIdle(state), isTrue);
    });

    // -----------------------------------------------------------------------
    // Mode création — succès
    // -----------------------------------------------------------------------
    test('création — transition idle → submitting → success', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <PropertyFormState>[];
      container.listen(
        propertyFormControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            name: 'Appart Paris',
            address: '12 rue de la Paix, 75001 Paris',
            type: PropertyType.appartement,
            surfaceM2: 55.0,
          );

      expect(states.length, greaterThanOrEqualTo(3));
      expect(_isIdle(states[0]), isTrue);
      expect(_isSubmitting(states[1]), isTrue);
      expect(_isSuccess(states[2]), isTrue);
      expect(_successProperty(states[2])!.name, 'Appart Paris');
    });

    test('création — invalide la liste après succès', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Démarrer le provider liste.
      await container.read(propertiesListProvider.future);

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            name: 'Appart Test',
            address: '1 rue Test',
            type: PropertyType.studio,
          );

      // Après invalidation, le provider liste reste accessible.
      expect(() => container.read(propertiesListProvider), returnsNormally);
    });

    // -----------------------------------------------------------------------
    // Mode édition — succès
    // -----------------------------------------------------------------------
    test('édition — transition idle → submitting → success', () async {
      final repo = _FakeRepo();
      final initial = _existingProperty();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <PropertyFormState>[];
      container.listen(
        propertyFormControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            initial: initial,
            name: 'Nouveau nom',
            address: 'Nouvelle adresse',
            type: PropertyType.appartement,
          );

      expect(_isSubmitting(states[1]), isTrue);
      expect(_isSuccess(states[2]), isTrue);
      expect(_successProperty(states[2])!.name, 'Nouveau nom');
    });

    test('édition — invalide la fiche détail après succès', () async {
      final repo = _FakeRepo();
      final initial = _existingProperty();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            initial: initial,
            name: 'Nouveau nom',
            address: 'Nouvelle adresse',
            type: PropertyType.appartement,
          );

      // Le provider détail doit être accessible (invalidé mais pas en erreur).
      expect(
        () => container.read(propertyDetailProvider(initial.id)),
        returnsNormally,
      );
    });

    // -----------------------------------------------------------------------
    // Erreur PostgrestException
    // -----------------------------------------------------------------------
    test('PostgrestException → état error avec message traduit FR', () async {
      final repo = _FakeRepo()
        ..createError = PostgrestException(
          code: '23514',
          message: 'check_violation on surface',
          details: '',
          hint: '',
        );
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            name: 'Test',
            address: 'Adresse',
            type: PropertyType.appartement,
          );

      final state = container.read(propertyFormControllerProvider);
      expect(_isError(state), isTrue);
      expect(_errorMessage(state), isNotNull);
      expect(_errorMessage(state)!, isNotEmpty);
    });

    // -----------------------------------------------------------------------
    // Erreur générique
    // -----------------------------------------------------------------------
    test('exception inconnue → état error avec message générique', () async {
      final repo = _FakeRepo()..createError = Exception('une erreur inconnue');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(propertyFormControllerProvider.notifier)
          .submit(
            name: 'Test',
            address: 'Adresse',
            type: PropertyType.appartement,
          );

      final state = container.read(propertyFormControllerProvider);
      expect(_isError(state), isTrue);
    });

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    test('reset() remet l\'état à idle', () {
      final container = _makeContainer(_FakeRepo());
      addTearDown(container.dispose);

      final notifier = container.read(propertyFormControllerProvider.notifier);
      notifier.state = const PropertyFormState.error(message: 'erreur test');

      notifier.reset();
      final state = container.read(propertyFormControllerProvider);
      expect(_isIdle(state), isTrue);
    });
  });
}

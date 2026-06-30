import 'package:easyrent/features/tenants/application/tenant_detail_provider.dart';
import 'package:easyrent/features/tenants/application/tenant_form_controller.dart';
import 'package:easyrent/features/tenants/application/tenants_list_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_form_state.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements TenantRepository {
  Tenant? _stored;
  Exception? createError;

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async {
    if (createError != null) throw createError!;
    _stored = _make(
      id: 'new-id',
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
    );
    return _stored!;
  }

  @override
  Future<Tenant> update(Tenant tenant) async {
    _stored = tenant;
    return tenant;
  }

  @override
  Future<List<Tenant>> list() async => _stored == null ? [] : [_stored!];

  @override
  Future<Tenant> getById(String id) async {
    if (_stored == null) throw TenantNotFoundException(id);
    return _stored!;
  }

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async =>
      _stored == null ? [] : [TenantListItem(tenant: _stored!)];

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];

  static Tenant _make({
    String id = 'test-id',
    String firstName = 'Jean',
    String lastName = 'Dupont',
    String email = 'jean@test.com',
    String? phone,
  }) => Tenant(
    id: id,
    landlordId: 'owner',
    firstName: firstName,
    lastName: lastName,
    email: email,
    phone: phone,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeRepo repo) => ProviderContainer(
  overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
);

Tenant _existingTenant() => Tenant(
  id: 'existing-id',
  landlordId: 'owner',
  firstName: 'Marie',
  lastName: 'Martin',
  email: 'marie@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

bool _isIdle(TenantFormState s) =>
    s.maybeWhen(idle: () => true, orElse: () => false);
bool _isSubmitting(TenantFormState s) =>
    s.maybeWhen(submitting: () => true, orElse: () => false);
bool _isSuccess(TenantFormState s) =>
    s.maybeWhen(success: (_) => true, orElse: () => false);
bool _isError(TenantFormState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

Tenant? _successTenant(TenantFormState s) =>
    s.maybeWhen(success: (t) => t, orElse: () => null);

String? _errorMessage(TenantFormState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => null);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantFormController', () {
    // -----------------------------------------------------------------------
    // État initial
    // -----------------------------------------------------------------------
    test('état initial est idle', () {
      final container = _makeContainer(_FakeRepo());
      addTearDown(container.dispose);

      final state = container.read(tenantFormControllerProvider);
      expect(_isIdle(state), isTrue);
    });

    // -----------------------------------------------------------------------
    // Création — succès
    // -----------------------------------------------------------------------
    test('création — transition idle → submitting → success', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <TenantFormState>[];
      container.listen(
        tenantFormControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            firstName: 'Jean',
            lastName: 'Dupont',
            email: 'jean@test.com',
          );

      expect(states.length, greaterThanOrEqualTo(3));
      expect(_isIdle(states[0]), isTrue);
      expect(_isSubmitting(states[1]), isTrue);
      expect(_isSuccess(states[2]), isTrue);
      expect(_successTenant(states[2])!.firstName, 'Jean');
    });

    test('création — invalide tenantsListProvider après succès', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Démarrer le provider liste.
      await container.read(tenantsListProvider.future);

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            firstName: 'Jean',
            lastName: 'Dupont',
            email: 'jean@test.com',
          );

      expect(() => container.read(tenantsListProvider), returnsNormally);
    });

    // -----------------------------------------------------------------------
    // Édition — succès
    // -----------------------------------------------------------------------
    test('édition — transition idle → submitting → success', () async {
      final repo = _FakeRepo();
      final initial = _existingTenant();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <TenantFormState>[];
      container.listen(
        tenantFormControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            initial: initial,
            firstName: 'Sophie',
            lastName: 'Martin',
            email: 'sophie@test.com',
          );

      expect(_isSubmitting(states[1]), isTrue);
      expect(_isSuccess(states[2]), isTrue);
      expect(_successTenant(states[2])!.firstName, 'Sophie');
    });

    test('édition — invalide tenantDetailProvider après succès', () async {
      final repo = _FakeRepo();
      final initial = _existingTenant();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            initial: initial,
            firstName: 'Sophie',
            lastName: 'Martin',
            email: 'sophie@test.com',
          );

      expect(
        () => container.read(tenantDetailProvider(initial.id)),
        returnsNormally,
      );
    });

    // -----------------------------------------------------------------------
    // Erreur FirebaseFunctionsException
    // -----------------------------------------------------------------------
    test(
      'FirebaseFunctionsException → état error avec message traduit FR',
      () async {
        final repo = _FakeRepo()
          ..createError = FirebaseFunctionsException(
            code: '23514',
            message: 'check_violation',
          );
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        await container
            .read(tenantFormControllerProvider.notifier)
            .submit(
              firstName: 'Jean',
              lastName: 'Dupont',
              email: 'jean@test.com',
            );

        final state = container.read(tenantFormControllerProvider);
        expect(_isError(state), isTrue);
        expect(_errorMessage(state), isNotNull);
        expect(_errorMessage(state)!, isNotEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Erreur générique
    // -----------------------------------------------------------------------
    test('exception inconnue → état error avec message générique', () async {
      final repo = _FakeRepo()..createError = Exception('réseau indisponible');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            firstName: 'Jean',
            lastName: 'Dupont',
            email: 'jean@test.com',
          );

      final state = container.read(tenantFormControllerProvider);
      expect(_isError(state), isTrue);
    });

    // -----------------------------------------------------------------------
    // TenantNotFoundException lors d'un update
    // -----------------------------------------------------------------------
    test('TenantNotFoundException → état error avec message localisé', () async {
      final repo = _FakeRepo()
        ..createError = const TenantNotFoundException('missing-id');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(tenantFormControllerProvider.notifier)
          .submit(
            firstName: 'Jean',
            lastName: 'Dupont',
            email: 'jean@test.com',
          );

      final state = container.read(tenantFormControllerProvider);
      expect(_isError(state), isTrue);
      // Le message doit mentionner "archivé" ou "introuvable" (vérification FR).
      final msg = _errorMessage(state)!.toLowerCase();
      expect(msg.contains('introuvable') || msg.contains('archiv'), isTrue);
    });

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    test('reset() remet l\'état à idle', () {
      final container = _makeContainer(_FakeRepo());
      addTearDown(container.dispose);

      final notifier = container.read(tenantFormControllerProvider.notifier);
      notifier.state = const TenantFormState.error(message: 'erreur test');

      notifier.reset();
      expect(_isIdle(container.read(tenantFormControllerProvider)), isTrue);
    });
  });
}

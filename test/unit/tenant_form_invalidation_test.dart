/// Non-régression du bug « liste des locataires vide après création »
/// (2026-07-02) : le formulaire invalidait l'ancien [tenantsListProvider]
/// mais PAS [tenantsListItemsProvider] que lit la page « Mes locataires »
/// (refonte cards FEAT-012) — si la liste avait déjà été visitée, son cache
/// vide n'était jamais rafraîchi.
///
/// Le test pilote un vrai [ProviderContainer] : il amorce les deux caches,
/// crée un locataire via le controller, puis vérifie que les deux listes
/// refetchent (un cache non invalidé renverrait la liste vide d'origine).
library;

import 'package:easyrent/features/tenants/application/tenant_form_controller.dart';
import 'package:easyrent/features/tenants/application/tenants_list_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake mutable : [create] ajoute au magasin interne que [list] et
/// [listWithActiveLeases] relisent — un refetch post-création voit donc le
/// nouveau locataire, un cache périmé non.
class _MutableFakeTenantRepo implements TenantRepository {
  final List<Tenant> _store = [];

  @override
  Future<List<Tenant>> list() async => List.of(_store);

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async =>
      _store.map((t) => TenantListItem(tenant: t)).toList();

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
    final tenant = Tenant(
      id: 't-${_store.length + 1}',
      landlordId: 'lld-1',
      firstName: firstName,
      lastName: lastName,
      email: email,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _store.add(tenant);
    return tenant;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('création locataire → tenantsListItemsProvider (page cards) ET '
      'tenantsListProvider (picker bail) refetchent', () async {
    final repo = _MutableFakeTenantRepo();
    final container = ProviderContainer(
      overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    // Amorce les caches (simule une visite préalable des pages).
    expect(await container.read(tenantsListItemsProvider.future), isEmpty);
    expect(await container.read(tenantsListProvider.future), isEmpty);

    await container
        .read(tenantFormControllerProvider.notifier)
        .submit(firstName: 'Marie', lastName: 'Durand', email: 'm@d.fr');

    expect(
      await container.read(tenantsListItemsProvider.future),
      hasLength(1),
      reason:
          'cache de la liste cards jamais invalidé après création — '
          'la page « Mes locataires » resterait vide',
    );
    expect(
      await container.read(tenantsListProvider.future),
      hasLength(1),
      reason: 'cache du picker bail jamais invalidé après création',
    );
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/tenant_repository.dart';
import '../domain/tenant.dart';
import '../domain/tenant_list_item.dart';

final _log = Logger('TenantsListNotifier');

/// Notifier qui charge et expose la liste des locataires du landlord courant.
///
/// Expose une méthode [refresh] pour recharger la liste après une action
/// (création, modification, archivage).
class TenantsListNotifier extends AsyncNotifier<List<Tenant>> {
  @override
  Future<List<Tenant>> build() async {
    return _fetch();
  }

  Future<List<Tenant>> _fetch() async {
    _log.info('fetch tenants list');
    return ref.read(tenantRepositoryProvider).list();
  }

  /// Recharge la liste depuis Supabase.
  ///
  /// À appeler après une création, modification ou archivage réussis.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Provider de la liste des locataires.
final tenantsListProvider =
    AsyncNotifierProvider<TenantsListNotifier, List<Tenant>>(
      TenantsListNotifier.new,
    );

// ---------------------------------------------------------------------------
// Nouveau provider Phase 3 — liste enrichie avec baux actifs
// ---------------------------------------------------------------------------

final _logItems = Logger('TenantsListItemsNotifier');

/// Notifier qui charge et expose la liste enrichie des locataires (avec baux actifs).
///
/// Utilise [TenantRepository.listWithActiveLeases] pour obtenir les [TenantListItem].
/// Conserve [tenantsListProvider] intact pour les autres consommateurs (LeaseForm picker).
class TenantsListItemsNotifier extends AsyncNotifier<List<TenantListItem>> {
  @override
  Future<List<TenantListItem>> build() async {
    return _fetch();
  }

  Future<List<TenantListItem>> _fetch() async {
    _logItems.info('fetch tenants list items');
    return ref.read(tenantRepositoryProvider).listWithActiveLeases();
  }

  /// Recharge la liste depuis Supabase.
  ///
  /// À appeler après une création, modification ou archivage réussis.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Provider de la liste enrichie des locataires (Phase 3).
///
/// Nouveau provider — n'affecte pas [tenantsListProvider].
final tenantsListItemsProvider =
    AsyncNotifierProvider<TenantsListItemsNotifier, List<TenantListItem>>(
      TenantsListItemsNotifier.new,
    );

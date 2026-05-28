import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/tenant_repository.dart';
import '../domain/tenant.dart';

final _log = Logger('TenantDetailNotifier');

/// Notifier qui charge un locataire par son [id].
///
/// Lance [TenantNotFoundException] si la RLS retourne 0 ligne
/// (locataire archivé, non possédé, ou id inconnu — pas de fuite d'information).
class TenantDetailNotifier extends FamilyAsyncNotifier<Tenant, String> {
  @override
  Future<Tenant> build(String arg) async {
    _log.info('fetch tenant detail id=$arg');
    return ref.read(tenantRepositoryProvider).getById(arg);
  }

  /// Recharge la fiche depuis Supabase.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tenantRepositoryProvider).getById(arg),
    );
  }
}

/// Provider de la fiche d'un locataire, paramétré par l'id.
final tenantDetailProvider =
    AsyncNotifierProviderFamily<TenantDetailNotifier, Tenant, String>(
      TenantDetailNotifier.new,
    );

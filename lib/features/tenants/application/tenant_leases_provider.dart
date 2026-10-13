import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tenant_repository.dart';

/// Baux d'un locataire (métadonnées brutes, dont `payment_day`), exposés en
/// provider pour les consommateurs Riverpod (ex. l'indicateur de ponctualité
/// agrégé). Thin wrapper sur [TenantRepository.listLeasesForTenant].
final tenantLeasesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tenantId) {
      return ref.read(tenantRepositoryProvider).listLeasesForTenant(tenantId);
    });

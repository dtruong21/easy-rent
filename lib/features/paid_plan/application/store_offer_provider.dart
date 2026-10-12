import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/store_billing_service.dart';
import '../domain/store_billing_models.dart';

/// Offre Pro du store (FEAT-044e), relue à chaque ouverture de l'écran
/// d'achat. `null` = indisponible.
final storeProOfferProvider = FutureProvider.autoDispose<ProStoreOffer?>(
  (ref) => ref.read(storeBillingServiceProvider).fetchProOffer(),
);

/// `true` si le store rapporte déjà un abonnement actif pour le compte
/// connecté (achat fait, activation serveur pas encore visible) : l'écran
/// reprend alors l'attente au lieu de reproposer l'achat. N'accorde aucun
/// droit. Relu à chaque ouverture de l'écran d'achat.
final storeActiveEntitlementProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final uid = ref.read(authRepositoryProvider).currentUser?.uid;
  if (uid == null) return false;
  return ref.read(storeBillingServiceProvider).hasActiveEntitlement(uid: uid);
});

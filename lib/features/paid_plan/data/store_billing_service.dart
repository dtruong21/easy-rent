import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/store_billing_models.dart';
import 'revenuecat_store_billing_service.dart';

/// Achat intégré des apps iOS/Android (FEAT-044e). Toutes les méthodes sont
/// sans effet (ou rendent une issue neutre) tant que le service n'est pas
/// configuré — c'est-à-dire tant que l'achat intégré est coupé.
abstract interface class StoreBillingService {
  /// Une fois, au démarrage. Sans effet si l'achat intégré est coupé.
  Future<void> configure();

  /// Rattache les achats au compte [uid] (compte complet uniquement). Lève si
  /// RevenueCat n'a pas pu rattacher le compte (réseau…), pour que l'appelant
  /// réessaie ; sans effet (ne lève pas) si le service n'est pas configuré.
  /// Toutes les autres méthodes gardent leur contrat « résultat neutre ».
  Future<void> logIn(String uid);

  /// Détache le compte courant (déconnexion, passage anonyme).
  Future<void> logOut();

  /// Offre Pro courante, prix lus dans le store ; `null` si indisponible.
  Future<ProStoreOffer?> fetchProOffer();

  /// Achète [package] pour le compte [uid]. Garantit d'abord que
  /// l'utilisateur RevenueCat est [uid] (jamais d'achat sur un identifiant
  /// anonyme) ; sinon `PurchaseFailed('not_logged_in')`. Ne lève jamais.
  Future<PurchaseOutcome> purchase(
    ProStorePackage package, {
    required String uid,
  });

  /// Restaure les achats du compte store pour [uid] (même garantie de
  /// rattachement que [purchase]). Ne lève jamais.
  Future<RestoreOutcome> restore({required String uid});

  /// Page de gestion de l'abonnement dans le store, si connue.
  Future<Uri?> managementUrl();
}

final storeBillingServiceProvider = Provider<StoreBillingService>(
  (ref) => RevenueCatStoreBillingService(),
);

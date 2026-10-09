import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/store_billing_models.dart';
import 'revenuecat_store_billing_service.dart';

/// Achat intégré des apps iOS/Android (FEAT-044e). Toutes les méthodes sont
/// sans effet (ou rendent une issue neutre) tant que le service n'est pas
/// configuré — c'est-à-dire tant que l'achat intégré est coupé.
abstract interface class StoreBillingService {
  /// Une fois, au démarrage. Sans effet si l'achat intégré est coupé.
  Future<void> configure();

  /// Rattache les achats au compte [uid] (compte complet uniquement).
  Future<void> logIn(String uid);

  /// Détache le compte courant (déconnexion, passage anonyme).
  Future<void> logOut();

  /// Offre Pro courante, prix lus dans le store ; `null` si indisponible.
  Future<ProStoreOffer?> fetchProOffer();

  Future<PurchaseOutcome> purchase(ProStorePackage package);

  Future<RestoreOutcome> restore();

  /// Page de gestion de l'abonnement dans le store, si connue.
  Future<Uri?> managementUrl();
}

final storeBillingServiceProvider = Provider<StoreBillingService>(
  (ref) => RevenueCatStoreBillingService(),
);

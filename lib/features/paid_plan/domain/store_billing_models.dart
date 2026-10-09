/// Modèles de l'achat intégré (FEAT-044e). Indépendants de
/// `purchases_flutter` : seul `RevenueCatStoreBillingService` importe le SDK.
library;

/// Périodicité d'une formule du store.
enum StoreBillingPeriod { monthly, annual }

/// Une formule achetable. [priceString] est LU DANS LE STORE (localisé) —
/// jamais les `priceLabel*` figés de `PlanMatrix`.
class ProStorePackage {
  const ProStorePackage({required this.period, required this.priceString});

  final StoreBillingPeriod period;
  final String priceString;
}

/// Offre Pro courante du store.
class ProStoreOffer {
  const ProStoreOffer({this.monthly, this.annual});

  final ProStorePackage? monthly;
  final ProStorePackage? annual;
}

/// Issue d'un achat. Le droit lui-même arrive par le serveur (webhook
/// RevenueCat → Firestore), jamais d'après cette issue.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

final class PurchaseSucceeded extends PurchaseOutcome {
  const PurchaseSucceeded();
}

final class PurchaseCancelled extends PurchaseOutcome {
  const PurchaseCancelled();
}

/// Contrôle parental, paiement différé : ni succès ni échec.
final class PurchasePending extends PurchaseOutcome {
  const PurchasePending();
}

final class PurchaseFailed extends PurchaseOutcome {
  const PurchaseFailed(this.code);

  /// Code technique (nom du `PurchasesErrorCode`, ou `not_configured` /
  /// `package_unavailable`) — journal et support, jamais affiché tel quel.
  final String code;
}

/// Issue de « Restaurer les achats ».
enum RestoreOutcome { success, nothingToRestore, error }

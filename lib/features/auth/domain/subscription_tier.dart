/// Palier d'abonnement du bailleur, persisté sur `landlords/{uid}.subscriptionTier`.
///
/// - [anonymous] : session Firebase Anonymous Auth (« essai sans compte »).
///   1 scénario simulateur sauvegardable max.
/// - [free] : compte complet (email/Google/Apple), aucun plan payant actif.
///   3 scénarios max.
/// - [paid] : Plan Pro (pas encore commercialisé au moment de BAILLAN-M1 —
///   la valeur existe pour préparer le terrain). Scénarios illimités.
enum SubscriptionTier {
  anonymous,
  free,
  paid;

  /// Parse la valeur brute Firestore (`String`). Retombe sur [anonymous]
  /// (le palier le plus restrictif) si la valeur est absente ou inconnue —
  /// fail-safe côté UX : mieux vaut sur-restreindre que sous-restreindre.
  static SubscriptionTier fromRaw(String? raw) {
    switch (raw) {
      case 'free':
        return SubscriptionTier.free;
      case 'paid':
        return SubscriptionTier.paid;
      case 'anonymous':
      default:
        return SubscriptionTier.anonymous;
    }
  }

  String get raw => switch (this) {
    SubscriptionTier.anonymous => 'anonymous',
    SubscriptionTier.free => 'free',
    SubscriptionTier.paid => 'paid',
  };

  /// Nombre maximum de scénarios simulateur sauvegardables. `null` = illimité.
  int? get scenarioLimit => switch (this) {
    SubscriptionTier.anonymous => 1,
    SubscriptionTier.free => 3,
    SubscriptionTier.paid => null,
  };

  /// Nombre maximum de biens (properties actives) créables. `null` = illimité.
  ///
  /// FEAT-044 (freemium) : le registre de biens est réservé aux comptes ;
  /// l'anonyme (simulateur seul) ne peut en créer aucun → 0. Le plafond est
  /// répliqué côté serveur dans la Cloud Function `createProperty`
  /// (`functions/src/callable/property_tenant.ts`) qui est la SOURCE DE VÉRITÉ
  /// du gating — ce getter ne sert qu'à désactiver le bouton "ajouter" côté UI.
  int? get propertyLimit => switch (this) {
    SubscriptionTier.anonymous => 0,
    SubscriptionTier.free => 2,
    SubscriptionTier.paid => null,
  };

  /// Nombre maximum de locataires actifs. `null` = illimité. Source de vérité
  /// serveur : Cloud Function `createTenant`. Voir [propertyLimit].
  int? get activeTenantLimit => switch (this) {
    SubscriptionTier.anonymous => 0,
    SubscriptionTier.free => 3,
    SubscriptionTier.paid => null,
  };

  /// Nombre maximum de baux ACTIFS. `null` = illimité. Source de vérité
  /// serveur : Cloud Function `createLease` / `updateLease`. Voir [propertyLimit].
  int? get activeLeaseLimit => switch (this) {
    SubscriptionTier.anonymous => 0,
    SubscriptionTier.free => 2,
    SubscriptionTier.paid => null,
  };
}

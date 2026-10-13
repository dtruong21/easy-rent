/// Classe d'accès du bailleur, persistée sur `landlords/{uid}.subscriptionTier`.
///
/// - [anonymous] : session Firebase Anonymous Auth (« essai sans compte »).
/// - [free] : compte complet (email/Google/Apple), aucun plan payant actif.
/// - [paid] : abonné payant — **classe d'accès uniquement** (FEAT-056 §1.2,
///   Option B). Le palier commercial précis (Pro/Max/Ultra) est porté par le
///   champ additif `planLevel`, modélisé côté Dart par
///   `PlanLevel`/`PlanEntitlement` (`plan_level.dart`, `plan_entitlement.dart`).
///   Les plafonds par palier vivent dans la table générée `plan_matrix.g.dart`
///   (source unique `config/entitlements.json`) — ce ne sont plus des getters
///   de cet enum.
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
}

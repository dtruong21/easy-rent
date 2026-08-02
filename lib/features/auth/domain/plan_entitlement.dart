import 'plan_level.dart';
import 'plan_matrix.g.dart';
import 'subscription_tier.dart';

/// Droits effectifs d'un compte : classe d'accès ([SubscriptionTier]) +
/// palier commercial ([PlanLevel]), résolus contre la table générée
/// [PlanMatrix] (FEAT-056 §1.5).
///
/// [atLeast] est le **seul** comparateur autorisé côté UI pour tester un
/// palier minimal ; ne jamais comparer `SubscriptionTier` à `paid` ni
/// l'`index` d'un enum Dart (l'ordre de déclaration n'est pas un contrat) —
/// le rang vient toujours de la table.
class PlanEntitlement {
  const PlanEntitlement({required this.tier, this.level})
    : assert(
        (tier == SubscriptionTier.paid) == (level != null),
        '`level` doit être non-null SSI `tier == SubscriptionTier.paid` '
        '(invariant I1, FEAT-056 §1.4).',
      );

  /// Classe d'accès brute (`landlords/{uid}.subscriptionTier`).
  final SubscriptionTier tier;

  /// Palier commercial. Non-null SSI [tier] == [SubscriptionTier.paid]
  /// (invariant I1).
  final PlanLevel? level;

  /// Construit depuis les valeurs brutes Firestore du doc landlord.
  factory PlanEntitlement.fromRaw({
    required SubscriptionTier tier,
    String? rawPlanLevel,
  }) {
    return PlanEntitlement(
      tier: tier,
      level: PlanLevel.fromRaw(rawPlanLevel, tier: tier),
    );
  }

  /// Clé d'indexation dans [PlanMatrix] : `anonymous`, `free`, ou l'id du
  /// palier payant.
  String get _key => switch (tier) {
    SubscriptionTier.anonymous => PlanMatrix.anonymousKey,
    SubscriptionTier.free => PlanMatrix.freeKey,
    SubscriptionTier.paid => level!.id,
  };

  /// Rang total : `anonymous` = 0, `free` = 1, sinon le rang du palier payant.
  int get rank => PlanMatrix.rankOf(_key);

  /// `true` si ce compte a au moins le palier [minLevel].
  bool atLeast(PlanLevel minLevel) => rank >= minLevel.rank;

  /// Plafond du quota pour ce compte. `null` = illimité.
  int? quota(PlanQuota quota) => PlanMatrix.quotaLimit(_key, quota);

  /// Ce compte a-t-il droit à cette feature ? `false` pour une feature
  /// `planned` (annoncée mais non construite), quel que soit le palier.
  bool has(PlanFeature feature) => PlanMatrix.hasFeature(_key, feature);

  @override
  bool operator ==(Object other) =>
      other is PlanEntitlement && other.tier == tier && other.level == level;

  @override
  int get hashCode => Object.hash(tier, level);

  @override
  String toString() => 'PlanEntitlement(tier: $tier, level: $level)';
}

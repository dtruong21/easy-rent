import 'plan_matrix.g.dart';
import 'subscription_tier.dart';

/// Palier commercial payant (FEAT-056 §1.5) — additif à [SubscriptionTier].
///
/// `subscriptionTier` reste la *classe d'accès* (`anonymous | free | paid`),
/// inchangée pour rester lisible par les clients déjà déployés. [PlanLevel]
/// précise QUEL palier payant est actif sur un compte `paid` ; il n'a de sens
/// que couplé à un [SubscriptionTier.paid] (invariant I1, cf.
/// `docs/plans/FEAT-056-multi-tier-subscriptions.md` §1.4).
enum PlanLevel {
  pro('pro'),
  max('max'),
  ultra('ultra');

  const PlanLevel(this.id);

  /// Identifiant de stockage (`landlords/{uid}.planLevel`) — clé de la table
  /// canonique `config/entitlements.json`.
  final String id;

  /// Rang total, lu dans la table générée [PlanMatrix] — **jamais** l'ordre
  /// de déclaration de cet enum, qui n'est pas un contrat (plan §1.5).
  int get rank => PlanMatrix.rankOf(id);

  /// Palier de repli pour le grandfathering (I3) et le fail-UP (I4) : le plus
  /// bas des paliers payants. Un compte `paid` sans palier connu du client
  /// (compte antérieur à FEAT-056, ou palier ajouté après cette build) est
  /// **toujours** traité comme au moins Pro — jamais comme non-payant.
  static const PlanLevel legacyFallback = PlanLevel.pro;

  static PlanLevel? _byId(String id) {
    for (final level in PlanLevel.values) {
      if (level.id == id) return level;
    }
    return null;
  }

  /// Dérive le palier depuis la valeur brute Firestore `planLevel` et la
  /// classe d'accès [tier] du même document.
  ///
  /// - `tier != paid` → `null` (I1 : non-null SSI `tier == paid`).
  /// - `tier == paid` et `raw` absent → [legacyFallback] (I3 — compte
  ///   antérieur à FEAT-056, jamais rétrogradé).
  /// - `tier == paid` et `raw` inconnu de cette build → [legacyFallback]
  ///   (I4 — fail-UP : une build plus ancienne que le palier reçu doit
  ///   sur-autoriser, **jamais** verrouiller un abonné qui paie).
  /// - `tier == paid` et `raw` connu → le palier correspondant.
  static PlanLevel? fromRaw(String? raw, {required SubscriptionTier tier}) {
    if (tier != SubscriptionTier.paid) return null;
    if (raw == null) return legacyFallback;
    return _byId(raw) ?? legacyFallback;
  }
}

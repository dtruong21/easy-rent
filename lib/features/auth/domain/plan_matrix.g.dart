// GENERATED — do not edit. Source: config/entitlements.json
// Regenerate: dart run tool/gen_entitlements.dart
// Guard: bash scripts/check-entitlements-parity.sh
//
// Miroir Dart de la table de droits (FEAT-056). Le jumeau
// TypeScript est functions/src/entitlements/plan_matrix.generated.ts ;
// les deux embarquent le même sourceSha.

/// Quotas déclarés dans la table canonique.
enum PlanQuota {
  properties('properties'),
  tenants('tenants'),
  activeLeases('activeLeases'),
  documents('documents'),
  scenarios('scenarios'),
  documentMaxBytes('documentMaxBytes');

  const PlanQuota(this.id);

  /// Clé du quota dans config/entitlements.json.
  final String id;
}

/// Features déclarées dans la table canonique.
enum PlanFeature {
  chargeRegularization('chargeRegularization'),
  scenarioComparison('scenarioComparison'),
  prioritySupport('prioritySupport'),
  paymentReminders('paymentReminders'),
  listings('listings'),
  accountingExport('accountingExport'),
  collaborators('collaborators');

  const PlanFeature(this.id);

  /// Clé de la feature dans config/entitlements.json.
  final String id;
}

/// Un palier commercial payant, tel que décrit par la table.
class PlanLevelSpec {
  const PlanLevelSpec({
    required this.id,
    required this.rank,
    required this.rcEntitlementId,
    required this.stripePriceParamMonthly,
    required this.stripePriceParamAnnual,
    required this.priceLabelMonthly,
    required this.priceLabelAnnual,
    required this.purchasable,
    required this.priceIndicative,
    required this.recommended,
  });

  /// Identifiant interne du palier (clé de stockage `planLevel`).
  final String id;

  /// Rang total. anonymous = 0, free = 1, paliers payants > 1.
  final int rank;

  /// Entitlement RevenueCat associé, `null` si pas encore créé.
  final String? rcEntitlementId;

  /// Nom du paramètre Firebase portant le price Stripe mensuel.
  final String stripePriceParamMonthly;

  /// Nom du paramètre Firebase portant le price Stripe annuel.
  final String stripePriceParamAnnual;

  /// Prix mensuel affiché (déjà formaté).
  final String priceLabelMonthly;

  /// Prix annuel affiché (déjà formaté).
  final String priceLabelAnnual;

  /// `false` = palier affiché mais non vendable (aucun chemin de paiement).
  final bool purchasable;

  /// `true` = prix annoncé comme indicatif, pas comme tarif ferme.
  final bool priceIndicative;

  /// `true` = palier mis en avant sur la page de pricing.
  final bool recommended;
}

/// Table de droits générée — lookups purs, aucune E/S.
///
/// Toutes les fonctions prennent une **clé de palier effectif**
/// (`anonymous`, `free`, ou un id de palier payant), JAMAIS un
/// `subscriptionTier` brut : indexer sur la classe d'accès rendrait la
/// différenciation entre paliers payants inexprimable.
class PlanMatrix {
  const PlanMatrix._();

  /// Version de schéma de la table canonique.
  static const int schemaVersion = 1;

  /// SHA-256 de config/entitlements.json au moment de la génération.
  static const String sourceSha =
      '9455bd6767a8b1865b9ca7271ec88db71d60fb965893ee8a36f549254925e1c0';

  /// Clé de palier des sessions anonymes.
  static const String anonymousKey = 'anonymous';

  /// Clé de palier des comptes complets non payants.
  static const String freeKey = 'free';

  /// Paliers payants, par rang croissant.
  static const List<PlanLevelSpec> levels = <PlanLevelSpec>[
    PlanLevelSpec(
      id: 'pro',
      rank: 10,
      rcEntitlementId: 'Bailan Pro',
      stripePriceParamMonthly: 'STRIPE_PRICE_PRO_MONTHLY',
      stripePriceParamAnnual: 'STRIPE_PRICE_PRO_ANNUAL',
      priceLabelMonthly: '7,99 €',
      priceLabelAnnual: '79 €',
      purchasable: true,
      priceIndicative: false,
      recommended: false,
    ),
    PlanLevelSpec(
      id: 'max',
      rank: 20,
      rcEntitlementId: 'Baillan Max',
      stripePriceParamMonthly: 'STRIPE_PRICE_MAX_MONTHLY',
      stripePriceParamAnnual: 'STRIPE_PRICE_MAX_ANNUAL',
      priceLabelMonthly: '14,99 €',
      priceLabelAnnual: '149 €',
      purchasable: false,
      priceIndicative: true,
      recommended: true,
    ),
    PlanLevelSpec(
      id: 'ultra',
      rank: 30,
      rcEntitlementId: 'Baillan Ultra',
      stripePriceParamMonthly: 'STRIPE_PRICE_ULTRA_MONTHLY',
      stripePriceParamAnnual: 'STRIPE_PRICE_ULTRA_ANNUAL',
      priceLabelMonthly: '24,99 €',
      priceLabelAnnual: '249 €',
      purchasable: false,
      priceIndicative: true,
      recommended: false,
    ),
  ];

  static const Map<String, int> _ranks = <String, int>{
    'anonymous': 0,
    'free': 1,
    'pro': 10,
    'max': 20,
    'ultra': 30,
  };

  static const Map<PlanQuota, Map<String, int?>> _quotaValues =
      <PlanQuota, Map<String, int?>>{
        PlanQuota.properties: <String, int?>{
          'anonymous': 0,
          'free': 2,
          'pro': 5,
          'max': 15,
          'ultra': null,
        },
        PlanQuota.tenants: <String, int?>{
          'anonymous': 0,
          'free': 3,
          'pro': 8,
          'max': 20,
          'ultra': null,
        },
        PlanQuota.activeLeases: <String, int?>{
          'anonymous': 0,
          'free': 2,
          'pro': 5,
          'max': 15,
          'ultra': null,
        },
        PlanQuota.documents: <String, int?>{
          'anonymous': 0,
          'free': 10,
          'pro': 50,
          'max': 150,
          'ultra': null,
        },
        PlanQuota.scenarios: <String, int?>{
          'anonymous': 1,
          'free': 3,
          'pro': 15,
          'max': 30,
          'ultra': null,
        },
        PlanQuota.documentMaxBytes: <String, int?>{
          'anonymous': 0,
          'free': 10485760,
          'pro': 10485760,
          'max': 26214400,
          'ultra': 52428800,
        },
      };

  static const Map<PlanQuota, String> _quotaErrorCodes = <PlanQuota, String>{
    PlanQuota.properties: 'property_limit_reached',
    PlanQuota.tenants: 'tenant_limit_reached',
    PlanQuota.activeLeases: 'lease_limit_reached',
    PlanQuota.documents: 'document_limit_reached',
    PlanQuota.scenarios: 'scenario_limit_reached',
    PlanQuota.documentMaxBytes: 'file_too_large',
  };

  static const Map<PlanQuota, String> _quotaUnits = <PlanQuota, String>{
    PlanQuota.properties: 'count',
    PlanQuota.tenants: 'count',
    PlanQuota.activeLeases: 'count',
    PlanQuota.documents: 'count',
    PlanQuota.scenarios: 'count',
    PlanQuota.documentMaxBytes: 'bytes',
  };

  static const Map<PlanQuota, String> _quotaEnforcement = <PlanQuota, String>{
    PlanQuota.properties: 'server',
    PlanQuota.tenants: 'server',
    PlanQuota.activeLeases: 'server',
    PlanQuota.documents: 'server',
    PlanQuota.scenarios: 'server',
    PlanQuota.documentMaxBytes: 'server',
  };

  static const Map<PlanFeature, String> _featureMinLevel =
      <PlanFeature, String>{
        PlanFeature.chargeRegularization: 'pro',
        PlanFeature.scenarioComparison: 'pro',
        PlanFeature.prioritySupport: 'max',
        PlanFeature.paymentReminders: 'max',
        PlanFeature.listings: 'max',
        PlanFeature.accountingExport: 'ultra',
        PlanFeature.collaborators: 'ultra',
      };

  static const Map<PlanFeature, String> _featureStatus = <PlanFeature, String>{
    PlanFeature.chargeRegularization: 'shipped',
    PlanFeature.scenarioComparison: 'shipped',
    PlanFeature.prioritySupport: 'shipped',
    PlanFeature.paymentReminders: 'planned',
    PlanFeature.listings: 'planned',
    PlanFeature.accountingExport: 'planned',
    PlanFeature.collaborators: 'planned',
  };

  static const Map<PlanFeature, String> _featureEnforcement =
      <PlanFeature, String>{
        PlanFeature.chargeRegularization: 'client',
        PlanFeature.scenarioComparison: 'client',
        PlanFeature.prioritySupport: 'none',
        PlanFeature.paymentReminders: 'server',
        PlanFeature.listings: 'server',
        PlanFeature.accountingExport: 'server',
        PlanFeature.collaborators: 'server',
      };

  /// Rang du palier effectif. Clé inconnue → 0 (fail-closed).
  static int rankOf(String planKey) => _ranks[planKey] ?? 0;

  /// Id du palier payant portant exactement ce rang, `null` sinon.
  static String? levelForRank(int rank) {
    for (final level in levels) {
      if (level.rank == rank) return level.id;
    }
    return null;
  }

  /// Plafond du quota pour ce palier effectif. `null` = illimité.
  /// Clé de palier inconnue → 0 (fail-closed : on sur-restreint, jamais
  /// l'inverse).
  static int? quotaLimit(String planKey, PlanQuota quota) {
    final values = _quotaValues[quota];
    if (values == null || !values.containsKey(planKey)) return 0;
    return values[planKey];
  }

  /// Code d'erreur contractuel du quota (partagé serveur ↔ client).
  static String errorCodeFor(PlanQuota quota) => _quotaErrorCodes[quota]!;

  /// `count` ou `bytes` — ne jamais additionner les deux familles.
  static String quotaUnit(PlanQuota quota) => _quotaUnits[quota]!;

  /// `server` | `client` | `none` — où le quota est réellement verrouillé.
  static String quotaEnforcement(PlanQuota quota) => _quotaEnforcement[quota]!;

  /// Palier minimal donnant droit à la feature.
  static String minLevelFor(PlanFeature feature) => _featureMinLevel[feature]!;

  /// `server` | `client` | `none` — où la feature est réellement verrouillée.
  static String featureEnforcement(PlanFeature feature) =>
      _featureEnforcement[feature]!;

  /// `false` tant que la feature est annoncée mais pas construite
  /// (`status: planned`).
  static bool isFeatureShipped(PlanFeature feature) =>
      _featureStatus[feature] == 'shipped';

  /// Ce palier effectif a-t-il droit à cette feature ?
  ///
  /// Renvoie `false` pour une feature `planned` QUEL QUE SOIT le palier, y
  /// compris le plus élevé : sinon on promet une fonctionnalité inexistante.
  static bool hasFeature(String planKey, PlanFeature feature) {
    if (!isFeatureShipped(feature)) return false;
    return rankOf(planKey) >= rankOf(minLevelFor(feature));
  }

  /// Palier payant correspondant à un entitlement RevenueCat.
  /// `null` = entitlement étranger → à ignorer, jamais à deviner.
  static String? levelForRcEntitlement(String rcEntitlementId) {
    for (final level in levels) {
      if (level.rcEntitlementId == rcEntitlementId) return level.id;
    }
    return null;
  }

  /// Spécification d'un palier payant, `null` si l'id est inconnu.
  static PlanLevelSpec? levelSpec(String levelId) {
    for (final level in levels) {
      if (level.id == levelId) return level;
    }
    return null;
  }

  /// Ce palier est-il ouvert à la vente ? Id inconnu → `false`.
  static bool isPurchasable(String levelId) =>
      levelSpec(levelId)?.purchasable ?? false;

  /// Plus petit palier payant dont le plafond couvre `needed` — sert à
  /// l'upsell contextuel (« passez à Max pour 25 Mio »). `null` si aucun
  /// palier ne suffit : ne jamais proposer un palier qui ne débloquerait rien.
  static String? minLevelForQuota(PlanQuota quota, int needed) {
    for (final level in levels) {
      final limit = quotaLimit(level.id, quota);
      if (limit == null || limit >= needed) return level.id;
    }
    return null;
  }
}

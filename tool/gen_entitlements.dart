// Générateur du miroir Dart de la table de droits (FEAT-056, plan §2.2).
//
//   dart run tool/gen_entitlements.dart
//
// Lit `config/entitlements.json` (SOURCE CANONIQUE UNIQUE) et écrit
// `lib/features/auth/domain/plan_matrix.g.dart`. Son jumeau TypeScript est
// `functions/tool/gen_entitlements.mjs` : les deux appliquent EXACTEMENT les
// mêmes validations et embarquent le même `sourceSha`, ce que
// `scripts/check-entitlements-parity.sh` vérifie en CI.
//
// Pourquoi générer plutôt qu'importer le JSON des deux côtés : le fichier est
// hors `functions/` (donc hors du bundle déployé) et le runtime web Flutter n'a
// pas d'accès disque. La génération règle les deux cas — et rend la divergence
// client/serveur *inexprimable* plutôt que simplement détectable.
//
// Le fichier généré est passé à `dart format` : la CI exécute
// `dart format --set-exit-if-changed .` sur tout le dépôt, fichiers générés
// compris.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'entitlements_schema.dart';

Future<void> main(List<String> args) async {
  final root = repoRoot();
  final sourceFile = File('$root/config/entitlements.json');
  if (!sourceFile.existsSync()) {
    stderr.writeln('❌ introuvable : ${sourceFile.path}');
    exit(1);
  }

  final bytes = sourceFile.readAsBytesSync();
  final sourceSha = sha256.convert(bytes).toString();

  final EntitlementsConfig config;
  try {
    config = EntitlementsConfig.parse(
      json.decode(utf8.decode(bytes)) as Object?,
    );
  } on EntitlementsConfigError catch (e) {
    stderr.writeln('❌ config/entitlements.json invalide : ${e.message}');
    exit(1);
  }

  final outPath = '$root/lib/features/auth/domain/plan_matrix.g.dart';
  File(outPath).writeAsStringSync(_emit(config, sourceSha));

  // `dart format` (et pas une mise en forme artisanale) : le fichier généré
  // doit survivre au `dart format --set-exit-if-changed .` de la CI.
  final fmt = await Process.run('dart', ['format', outPath]);
  if (fmt.exitCode != 0) {
    stderr.writeln('❌ dart format a échoué : ${fmt.stderr}');
    exit(1);
  }

  stdout.writeln('✅ $outPath (sourceSha $sourceSha)');
}

String _dartString(String value) => "'${value.replaceAll("'", r"\'")}'";

String _dartNullableString(String? value) =>
    value == null ? 'null' : _dartString(value);

String _emit(EntitlementsConfig config, String sourceSha) {
  final buf = StringBuffer();

  buf.writeln('// GENERATED — do not edit. Source: config/entitlements.json');
  buf.writeln('// Regenerate: dart run tool/gen_entitlements.dart');
  buf.writeln('// Guard: bash scripts/check-entitlements-parity.sh');
  buf.writeln('//');
  buf.writeln('// Miroir Dart de la table de droits (FEAT-056). Le jumeau');
  buf.writeln(
    '// TypeScript est functions/src/entitlements/plan_matrix.generated.ts ;',
  );
  buf.writeln('// les deux embarquent le même sourceSha.');
  buf.writeln();
  buf.writeln('/// Quotas déclarés dans la table canonique.');
  buf.writeln('enum PlanQuota {');
  for (final q in config.quotas) {
    buf.writeln('  ${q.id}(${_dartString(q.id)}),');
  }
  buf.writeln('  ;');
  buf.writeln();
  buf.writeln('  const PlanQuota(this.id);');
  buf.writeln();
  buf.writeln('  /// Clé du quota dans config/entitlements.json.');
  buf.writeln('  final String id;');
  buf.writeln('}');
  buf.writeln();
  buf.writeln('/// Features déclarées dans la table canonique.');
  buf.writeln('enum PlanFeature {');
  for (final f in config.features) {
    buf.writeln('  ${f.id}(${_dartString(f.id)}),');
  }
  buf.writeln('  ;');
  buf.writeln();
  buf.writeln('  const PlanFeature(this.id);');
  buf.writeln();
  buf.writeln('  /// Clé de la feature dans config/entitlements.json.');
  buf.writeln('  final String id;');
  buf.writeln('}');
  buf.writeln();
  buf.writeln('/// Un palier commercial payant, tel que décrit par la table.');
  buf.writeln('class PlanLevelSpec {');
  buf.writeln('  const PlanLevelSpec({');
  buf.writeln('    required this.id,');
  buf.writeln('    required this.rank,');
  buf.writeln('    required this.rcEntitlementId,');
  buf.writeln('    required this.stripePriceParamMonthly,');
  buf.writeln('    required this.stripePriceParamAnnual,');
  buf.writeln('    required this.priceLabelMonthly,');
  buf.writeln('    required this.priceLabelAnnual,');
  buf.writeln('    required this.purchasable,');
  buf.writeln('    required this.priceIndicative,');
  buf.writeln('    required this.recommended,');
  buf.writeln('  });');
  buf.writeln();
  buf.writeln(
    '  /// Identifiant interne du palier (clé de stockage `planLevel`).',
  );
  buf.writeln('  final String id;');
  buf.writeln();
  buf.writeln(
    '  /// Rang total. anonymous = 0, free = 1, paliers payants > 1.',
  );
  buf.writeln('  final int rank;');
  buf.writeln();
  buf.writeln(
    '  /// Entitlement RevenueCat associé, `null` si pas encore créé.',
  );
  buf.writeln('  final String? rcEntitlementId;');
  buf.writeln();
  buf.writeln(
    '  /// Nom du paramètre Firebase portant le price Stripe mensuel.',
  );
  buf.writeln('  final String stripePriceParamMonthly;');
  buf.writeln();
  buf.writeln(
    '  /// Nom du paramètre Firebase portant le price Stripe annuel.',
  );
  buf.writeln('  final String stripePriceParamAnnual;');
  buf.writeln();
  buf.writeln('  /// Prix mensuel affiché (déjà formaté).');
  buf.writeln('  final String priceLabelMonthly;');
  buf.writeln();
  buf.writeln('  /// Prix annuel affiché (déjà formaté).');
  buf.writeln('  final String priceLabelAnnual;');
  buf.writeln();
  buf.writeln(
    '  /// `false` = palier affiché mais non vendable (aucun chemin de paiement).',
  );
  buf.writeln('  final bool purchasable;');
  buf.writeln();
  buf.writeln(
    '  /// `true` = prix annoncé comme indicatif, pas comme tarif ferme.',
  );
  buf.writeln('  final bool priceIndicative;');
  buf.writeln();
  buf.writeln('  /// `true` = palier mis en avant sur la page de pricing.');
  buf.writeln('  final bool recommended;');
  buf.writeln('}');
  buf.writeln();
  buf.writeln('/// Table de droits générée — lookups purs, aucune E/S.');
  buf.writeln('///');
  buf.writeln(
    '/// Toutes les fonctions prennent une **clé de palier effectif**',
  );
  buf.writeln(
    '/// (`anonymous`, `free`, ou un id de palier payant), JAMAIS un',
  );
  buf.writeln(
    '/// `subscriptionTier` brut : indexer sur la classe d\'accès rendrait la',
  );
  buf.writeln('/// différenciation entre paliers payants inexprimable.');
  buf.writeln('class PlanMatrix {');
  buf.writeln('  const PlanMatrix._();');
  buf.writeln();
  buf.writeln('  /// Version de schéma de la table canonique.');
  buf.writeln('  static const int schemaVersion = ${config.schemaVersion};');
  buf.writeln();
  buf.writeln(
    '  /// SHA-256 de config/entitlements.json au moment de la génération.',
  );
  buf.writeln('  static const String sourceSha = ${_dartString(sourceSha)};');
  buf.writeln();
  buf.writeln('  /// Clé de palier des sessions anonymes.');
  buf.writeln(
    '  static const String anonymousKey = ${_dartString(kAnonymousKey)};',
  );
  buf.writeln();
  buf.writeln('  /// Clé de palier des comptes complets non payants.');
  buf.writeln('  static const String freeKey = ${_dartString(kFreeKey)};');
  buf.writeln();
  buf.writeln('  /// Paliers payants, par rang croissant.');
  buf.writeln('  static const List<PlanLevelSpec> levels = <PlanLevelSpec>[');
  for (final l in config.levels) {
    buf.writeln('    PlanLevelSpec(');
    buf.writeln('      id: ${_dartString(l.id)},');
    buf.writeln('      rank: ${l.rank},');
    buf.writeln(
      '      rcEntitlementId: ${_dartNullableString(l.rcEntitlementId)},',
    );
    buf.writeln(
      '      stripePriceParamMonthly: ${_dartString(l.stripePriceParamMonthly)},',
    );
    buf.writeln(
      '      stripePriceParamAnnual: ${_dartString(l.stripePriceParamAnnual)},',
    );
    buf.writeln(
      '      priceLabelMonthly: ${_dartString(l.priceLabelMonthly)},',
    );
    buf.writeln('      priceLabelAnnual: ${_dartString(l.priceLabelAnnual)},');
    buf.writeln('      purchasable: ${l.purchasable},');
    buf.writeln('      priceIndicative: ${l.priceIndicative},');
    buf.writeln('      recommended: ${l.recommended},');
    buf.writeln('    ),');
  }
  buf.writeln('  ];');
  buf.writeln();
  buf.writeln('  static const Map<String, int> _ranks = <String, int>{');
  buf.writeln('    ${_dartString(kAnonymousKey)}: $kAnonymousRank,');
  buf.writeln('    ${_dartString(kFreeKey)}: $kFreeRank,');
  for (final l in config.levels) {
    buf.writeln('    ${_dartString(l.id)}: ${l.rank},');
  }
  buf.writeln('  };');
  buf.writeln();
  buf.writeln(
    '  static const Map<PlanQuota, Map<String, int?>> _quotaValues =',
  );
  buf.writeln('      <PlanQuota, Map<String, int?>>{');
  for (final q in config.quotas) {
    buf.writeln('        PlanQuota.${q.id}: <String, int?>{');
    for (final entry in q.values.entries) {
      buf.writeln('          ${_dartString(entry.key)}: ${entry.value},');
    }
    buf.writeln('        },');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.writeln('  static const Map<PlanQuota, String> _quotaErrorCodes =');
  buf.writeln('      <PlanQuota, String>{');
  for (final q in config.quotas) {
    buf.writeln('        PlanQuota.${q.id}: ${_dartString(q.errorCode)},');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.writeln(
    '  static const Map<PlanQuota, String> _quotaUnits = <PlanQuota, String>{',
  );
  for (final q in config.quotas) {
    buf.writeln('    PlanQuota.${q.id}: ${_dartString(q.unit)},');
  }
  buf.writeln('  };');
  buf.writeln();
  buf.writeln('  static const Map<PlanQuota, String> _quotaEnforcement =');
  buf.writeln('      <PlanQuota, String>{');
  for (final q in config.quotas) {
    buf.writeln('        PlanQuota.${q.id}: ${_dartString(q.enforcement)},');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.writeln('  static const Map<PlanFeature, String> _featureMinLevel =');
  buf.writeln('      <PlanFeature, String>{');
  for (final f in config.features) {
    buf.writeln('        PlanFeature.${f.id}: ${_dartString(f.minLevel)},');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.writeln('  static const Map<PlanFeature, String> _featureStatus =');
  buf.writeln('      <PlanFeature, String>{');
  for (final f in config.features) {
    buf.writeln('        PlanFeature.${f.id}: ${_dartString(f.status)},');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.writeln('  static const Map<PlanFeature, String> _featureEnforcement =');
  buf.writeln('      <PlanFeature, String>{');
  for (final f in config.features) {
    buf.writeln('        PlanFeature.${f.id}: ${_dartString(f.enforcement)},');
  }
  buf.writeln('      };');
  buf.writeln();
  buf.write(_staticApi);
  buf.writeln('}');

  return buf.toString();
}

/// Corps invariant de l'API (§2.4 du plan) — identique, nom pour nom, à celui
/// émis côté TypeScript pour que la revue croisée soit triviale.
const String _staticApi = r'''
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
''';

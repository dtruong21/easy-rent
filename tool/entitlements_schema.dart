// Lecture + validation de `config/entitlements.json` (FEAT-056, plan §2.2).
//
// Volontairement partagé par `tool/gen_entitlements.dart` UNIQUEMENT : le test
// de parité (`test/unit/plan_matrix_parity_test.dart`) relit le JSON brut sans
// passer par ce parseur, sinon un bug de parsing serait invisible des deux
// côtés à la fois.
//
// Les mêmes validations sont réimplémentées à l'identique dans
// `functions/tool/gen_entitlements.mjs`. Toute règle ajoutée ici doit l'être
// là-bas (et réciproquement) — `scripts/check-entitlements-parity.sh` compare
// les deux sorties, donc une divergence de validation finit par se voir.

import 'dart:io';

/// Clé de palier effectif des sessions anonymes.
const String kAnonymousKey = 'anonymous';

/// Clé de palier effectif des comptes complets non payants.
const String kFreeKey = 'free';

/// Rang du palier anonyme (le plus bas).
const int kAnonymousRank = 0;

/// Rang du palier gratuit.
const int kFreeRank = 1;

/// Valeurs autorisées pour `enforcement`.
const Set<String> kEnforcements = {'server', 'client', 'none'};

/// Valeurs autorisées pour `unit`.
const Set<String> kUnits = {'count', 'bytes'};

/// Valeurs autorisées pour `status`.
const Set<String> kStatuses = {'shipped', 'planned'};

/// Identifiants interdits comme id de quota/feature : ils entreraient en
/// collision avec des membres implicites d'enum (Dart) ou des mots-clés.
const Set<String> kReservedIds = {
  'values',
  'index',
  'name',
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
  'id',
  'default',
  'new',
  'class',
  'enum',
  'const',
  'var',
  'null',
  'true',
  'false',
};

/// Marqueurs de config incomplète : le générateur REFUSE de produire un miroir
/// qui en contient (§3.1 du plan) — impossible de déployer une table à trous.
const List<String> kPlaceholderMarkers = [
  'DÉFINIR',
  'DEFINIR',
  'TODO',
  'FIXME',
];

/// Échec de validation de la table canonique.
class EntitlementsConfigError implements Exception {
  /// Crée une erreur de validation avec son [message].
  EntitlementsConfigError(this.message);

  /// Description lisible du problème.
  final String message;

  @override
  String toString() => 'EntitlementsConfigError: $message';
}

Never _fail(String message) => throw EntitlementsConfigError(message);

/// Racine du dépôt git, déduite de l'emplacement de ce fichier
/// (`<root>/tool/entitlements_schema.dart`).
String repoRoot() {
  final script = Platform.script.toFilePath();
  // `dart run tool/gen_entitlements.dart` → script = <root>/tool/gen_...dart
  final dir = File(script).parent;
  if (dir.path.endsWith('tool')) return dir.parent.path;
  return Directory.current.path;
}

/// Un palier payant de la table canonique.
class LevelSpec {
  /// Crée la spécification d'un palier.
  LevelSpec({
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

  /// Identifiant interne (valeur stockée dans `landlords/{uid}.planLevel`).
  final String id;

  /// Rang total du palier.
  final int rank;

  /// Entitlement RevenueCat, `null` si pas encore créé au dashboard.
  final String? rcEntitlementId;

  /// Nom du paramètre Firebase du price Stripe mensuel.
  final String stripePriceParamMonthly;

  /// Nom du paramètre Firebase du price Stripe annuel.
  final String stripePriceParamAnnual;

  /// Prix mensuel affiché (chaîne déjà formatée).
  final String priceLabelMonthly;

  /// Prix annuel affiché (chaîne déjà formatée).
  final String priceLabelAnnual;

  /// Palier ouvert à la vente.
  final bool purchasable;

  /// Prix annoncé comme indicatif.
  final bool priceIndicative;

  /// Palier mis en avant sur la page de pricing.
  final bool recommended;
}

/// Un quota de la table canonique.
class QuotaSpec {
  /// Crée la spécification d'un quota.
  QuotaSpec({
    required this.id,
    required this.errorCode,
    required this.enforcement,
    required this.unit,
    required this.values,
  });

  /// Clé du quota.
  final String id;

  /// Code d'erreur renvoyé au client au dépassement.
  final String errorCode;

  /// `server` | `client` | `none`.
  final String enforcement;

  /// `count` | `bytes`.
  final String unit;

  /// Plafond par clé de palier effectif. `null` = illimité.
  final Map<String, int?> values;
}

/// Une feature de la table canonique.
class FeatureSpec {
  /// Crée la spécification d'une feature.
  FeatureSpec({
    required this.id,
    required this.minLevel,
    required this.enforcement,
    required this.status,
  });

  /// Clé de la feature.
  final String id;

  /// Palier payant minimal.
  final String minLevel;

  /// `server` | `client` | `none`.
  final String enforcement;

  /// `shipped` | `planned`.
  final String status;
}

/// La table canonique validée.
class EntitlementsConfig {
  /// Crée la table.
  EntitlementsConfig({
    required this.schemaVersion,
    required this.levels,
    required this.quotas,
    required this.features,
  });

  /// Version de schéma.
  final int schemaVersion;

  /// Paliers payants, par rang croissant.
  final List<LevelSpec> levels;

  /// Quotas, dans l'ordre de déclaration.
  final List<QuotaSpec> quotas;

  /// Features, dans l'ordre de déclaration.
  final List<FeatureSpec> features;

  /// Parse et VALIDE la table. Lève [EntitlementsConfigError] au moindre
  /// écart : mieux vaut casser la génération que produire un miroir à trous.
  static EntitlementsConfig parse(Object? raw) {
    if (raw is! Map<String, dynamic>) _fail('racine : objet JSON attendu');

    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int) _fail('schemaVersion : entier attendu');

    // --- levels -------------------------------------------------------------
    final rawLevels = raw['levels'];
    if (rawLevels is! List || rawLevels.isEmpty) {
      _fail('levels : liste non vide attendue');
    }
    final levels = <LevelSpec>[];
    final seenIds = <String>{};
    final seenRanks = <int>{};
    final seenRcIds = <String>{};
    for (final entry in rawLevels) {
      if (entry is! Map<String, dynamic>) _fail('levels[] : objet attendu');
      final id = _requireIdent(entry['id'], 'levels[].id');
      if (!seenIds.add(id)) _fail('levels : id dupliqué "$id"');
      final rank = entry['rank'];
      if (rank is! int) _fail('levels[$id].rank : entier attendu');
      if (rank <= kFreeRank) {
        _fail(
          'levels[$id].rank = $rank : un palier payant doit avoir un rang > '
          '$kFreeRank (invariant I5 — jamais de palier payant sous le gratuit)',
        );
      }
      if (!seenRanks.add(rank)) _fail('levels : rang dupliqué $rank');

      final rcRaw = entry['rcEntitlementId'];
      String? rcId;
      if (rcRaw != null) {
        rcId = _requireNonEmptyString(rcRaw, 'levels[$id].rcEntitlementId');
        if (!seenRcIds.add(rcId)) {
          _fail('levels : rcEntitlementId dupliqué "$rcId"');
        }
      }

      final stripe = entry['stripePriceParam'];
      if (stripe is! Map<String, dynamic>) {
        _fail('levels[$id].stripePriceParam : objet attendu');
      }
      final price = entry['priceLabel'];
      if (price is! Map<String, dynamic>) {
        _fail('levels[$id].priceLabel : objet attendu');
      }

      final purchasable = _requireBool(
        entry['purchasable'],
        'levels[$id].purchasable',
      );
      if (purchasable && rcId == null) {
        _fail(
          'levels[$id] : purchasable=true sans rcEntitlementId — un palier '
          'vendable sans entitlement RevenueCat encaisse sans jamais accorder '
          "l'accès",
        );
      }

      levels.add(
        LevelSpec(
          id: id,
          rank: rank,
          rcEntitlementId: rcId,
          stripePriceParamMonthly: _requireNonEmptyString(
            stripe['monthly'],
            'levels[$id].stripePriceParam.monthly',
          ),
          stripePriceParamAnnual: _requireNonEmptyString(
            stripe['annual'],
            'levels[$id].stripePriceParam.annual',
          ),
          priceLabelMonthly: _requireNonEmptyString(
            price['monthly'],
            'levels[$id].priceLabel.monthly',
          ),
          priceLabelAnnual: _requireNonEmptyString(
            price['annual'],
            'levels[$id].priceLabel.annual',
          ),
          purchasable: purchasable,
          priceIndicative: _requireBool(
            entry['priceIndicative'],
            'levels[$id].priceIndicative',
          ),
          recommended: _requireBool(
            entry['recommended'],
            'levels[$id].recommended',
          ),
        ),
      );
    }
    levels.sort((a, b) => a.rank.compareTo(b.rank));

    // Clés de palier effectif attendues dans CHAQUE quota : pas de trou
    // possible (un trou serait lu comme `undefined` → 0 ou ∞ selon le côté).
    final expectedKeys = <String>{kAnonymousKey, kFreeKey, ...seenIds};

    // --- quotas -------------------------------------------------------------
    final rawQuotas = raw['quotas'];
    if (rawQuotas is! Map<String, dynamic>) _fail('quotas : objet attendu');
    final quotas = <QuotaSpec>[];
    for (final entry in rawQuotas.entries) {
      if (entry.key.startsWith('_')) continue; // note documentaire
      final id = _requireIdent(entry.key, 'quotas.<id>');
      final spec = entry.value;
      if (spec is! Map<String, dynamic>) _fail('quotas.$id : objet attendu');

      final values = spec['values'];
      if (values is! Map<String, dynamic>) {
        _fail('quotas.$id.values : objet attendu');
      }
      final missing = expectedKeys.difference(values.keys.toSet());
      if (missing.isNotEmpty) {
        _fail(
          'quotas.$id.values : paliers manquants ${missing.toList()..sort()}',
        );
      }
      final extra = values.keys.toSet().difference(expectedKeys);
      if (extra.isNotEmpty) {
        _fail('quotas.$id.values : paliers inconnus ${extra.toList()..sort()}');
      }
      // Ordre déterministe (anonymous, free, puis paliers par rang croissant)
      // pour que la sortie générée ne dépende pas de l'ordre du JSON.
      final ordered = <String, int?>{};
      for (final key in [kAnonymousKey, kFreeKey, ...levels.map((l) => l.id)]) {
        final value = values[key];
        if (value != null && (value is! int || value < 0)) {
          _fail('quotas.$id.values.$key : entier >= 0 ou null attendu');
        }
        ordered[key] = value as int?;
      }

      quotas.add(
        QuotaSpec(
          id: id,
          errorCode: _requireNonEmptyString(
            spec['errorCode'],
            'quotas.$id.errorCode',
          ),
          enforcement: _requireEnum(
            spec['enforcement'],
            kEnforcements,
            'quotas.$id.enforcement',
          ),
          unit: _requireEnum(spec['unit'], kUnits, 'quotas.$id.unit'),
          values: ordered,
        ),
      );
    }
    if (quotas.isEmpty) _fail('quotas : au moins un quota attendu');

    // --- features -----------------------------------------------------------
    final rawFeatures = raw['features'];
    if (rawFeatures is! Map<String, dynamic>) _fail('features : objet attendu');
    final features = <FeatureSpec>[];
    for (final entry in rawFeatures.entries) {
      if (entry.key.startsWith('_')) continue;
      final id = _requireIdent(entry.key, 'features.<id>');
      final spec = entry.value;
      if (spec is! Map<String, dynamic>) _fail('features.$id : objet attendu');
      final minLevel = _requireNonEmptyString(
        spec['minLevel'],
        'features.$id.minLevel',
      );
      if (!seenIds.contains(minLevel)) {
        _fail('features.$id.minLevel : palier inconnu "$minLevel"');
      }
      features.add(
        FeatureSpec(
          id: id,
          minLevel: minLevel,
          enforcement: _requireEnum(
            spec['enforcement'],
            kEnforcements,
            'features.$id.enforcement',
          ),
          status: _requireEnum(
            spec['status'],
            kStatuses,
            'features.$id.status',
          ),
        ),
      );
    }

    return EntitlementsConfig(
      schemaVersion: schemaVersion,
      levels: levels,
      quotas: quotas,
      features: features,
    );
  }
}

String _requireNonEmptyString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    _fail('$path : chaîne non vide attendue');
  }
  final upper = value.toUpperCase();
  for (final marker in kPlaceholderMarkers) {
    if (upper.contains(marker)) {
      _fail(
        '$path : marqueur de config incomplète "$marker" — le générateur '
        'refuse de produire un miroir à trous',
      );
    }
  }
  return value;
}

String _requireIdent(Object? value, String path) {
  final s = _requireNonEmptyString(value, path);
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(s)) {
    _fail('$path : identifiant lowerCamelCase attendu, reçu "$s"');
  }
  if (kReservedIds.contains(s)) _fail('$path : identifiant réservé "$s"');
  return s;
}

bool _requireBool(Object? value, String path) {
  if (value is! bool) _fail('$path : booléen attendu');
  return value;
}

String _requireEnum(Object? value, Set<String> allowed, String path) {
  final s = _requireNonEmptyString(value, path);
  if (!allowed.contains(s)) {
    _fail('$path : valeur inconnue "$s" (attendu : ${allowed.join(" | ")})');
  }
  return s;
}

// Filet d'exécution de la garde de parité (FEAT-056, plan §2.2 et §10.1).
//
// `scripts/check-entitlements-parity.sh` prouve que le miroir Dart est bien
// LA SORTIE du générateur. Ce test prouve autre chose : que cette sortie dit
// bien ce que dit `config/entitlements.json`. Il relit donc le JSON BRUT
// depuis le disque, sans passer par `tool/entitlements_schema.dart` — sinon un
// bug de parsing serait invisible des deux côtés à la fois.
//
// Il échoue notamment si quelqu'un édite `plan_matrix.g.dart` à la main sans
// toucher au JSON (le générateur, lui, n'est pas rejoué par `flutter test`).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easyrent/features/auth/domain/plan_matrix.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// Clés de palier effectif attendues dans chaque quota.
const List<String> _planKeys = ['anonymous', 'free', 'pro', 'max', 'ultra'];

void main() {
  late File sourceFile;
  late Map<String, dynamic> config;

  setUpAll(() {
    sourceFile = File('config/entitlements.json');
    expect(
      sourceFile.existsSync(),
      isTrue,
      reason:
          'config/entitlements.json introuvable — `flutter test` doit être '
          'lancé depuis la racine du dépôt.',
    );
    config = json.decode(sourceFile.readAsStringSync()) as Map<String, dynamic>;
  });

  group('plan_matrix.g.dart ↔ config/entitlements.json', () {
    test('sourceSha correspond au JSON réellement présent', () {
      final actual = sha256.convert(sourceFile.readAsBytesSync()).toString();
      expect(
        PlanMatrix.sourceSha,
        actual,
        reason:
            'Le miroir Dart est périmé : relancer '
            '`dart run tool/gen_entitlements.dart`.',
      );
    });

    test('schemaVersion identique', () {
      expect(PlanMatrix.schemaVersion, config['schemaVersion']);
    });

    test('paliers : mêmes ids, mêmes rangs, mêmes champs', () {
      final rawLevels =
          (config['levels'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .toList()
            ..sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));

      expect(PlanMatrix.levels.length, rawLevels.length);
      for (var i = 0; i < rawLevels.length; i++) {
        final raw = rawLevels[i];
        final gen = PlanMatrix.levels[i];
        expect(gen.id, raw['id'], reason: 'levels[$i].id');
        expect(gen.rank, raw['rank'], reason: 'levels[${gen.id}].rank');
        expect(
          gen.rcEntitlementId,
          raw['rcEntitlementId'],
          reason: 'levels[${gen.id}].rcEntitlementId',
        );
        final stripe = raw['stripePriceParam'] as Map<String, dynamic>;
        expect(gen.stripePriceParamMonthly, stripe['monthly']);
        expect(gen.stripePriceParamAnnual, stripe['annual']);
        final price = raw['priceLabel'] as Map<String, dynamic>;
        expect(gen.priceLabelMonthly, price['monthly']);
        expect(gen.priceLabelAnnual, price['annual']);
        expect(gen.purchasable, raw['purchasable']);
        expect(gen.priceIndicative, raw['priceIndicative']);
        expect(gen.recommended, raw['recommended']);
      }
    });

    test('quotas : mêmes ids, mêmes métadonnées, mêmes valeurs par palier', () {
      final rawQuotas = (config['quotas'] as Map<String, dynamic>)
        ..removeWhere((key, _) => key.startsWith('_'));

      expect(
        PlanQuota.values.map((q) => q.id).toSet(),
        rawQuotas.keys.toSet(),
        reason: 'un quota a été ajouté/retiré du JSON sans régénérer',
      );

      for (final quota in PlanQuota.values) {
        final raw = rawQuotas[quota.id] as Map<String, dynamic>;
        expect(
          PlanMatrix.errorCodeFor(quota),
          raw['errorCode'],
          reason: '${quota.id}.errorCode',
        );
        expect(
          PlanMatrix.quotaUnit(quota),
          raw['unit'],
          reason: '${quota.id}.unit',
        );
        expect(
          PlanMatrix.quotaEnforcement(quota),
          raw['enforcement'],
          reason: '${quota.id}.enforcement',
        );

        final values = raw['values'] as Map<String, dynamic>;
        expect(
          values.keys.toSet(),
          _planKeys.toSet(),
          reason:
              '${quota.id}.values doit porter une valeur par PALIER EFFECTIF '
              '(pas par classe d\'accès) — un trou serait lu comme 0 ou ∞.',
        );
        for (final key in _planKeys) {
          expect(
            PlanMatrix.quotaLimit(key, quota),
            values[key],
            reason: '${quota.id}.values.$key',
          );
        }
      }
    });

    test('features : mêmes ids, mêmes minLevel/status/enforcement', () {
      final rawFeatures = (config['features'] as Map<String, dynamic>)
        ..removeWhere((key, _) => key.startsWith('_'));

      expect(
        PlanFeature.values.map((f) => f.id).toSet(),
        rawFeatures.keys.toSet(),
      );

      for (final feature in PlanFeature.values) {
        final raw = rawFeatures[feature.id] as Map<String, dynamic>;
        expect(PlanMatrix.minLevelFor(feature), raw['minLevel']);
        expect(PlanMatrix.featureEnforcement(feature), raw['enforcement']);
        expect(
          PlanMatrix.isFeatureShipped(feature),
          raw['status'] == 'shipped',
        );
      }
    });
  });

  group('sémantique de la table', () {
    test('rangs des classes non payantes', () {
      expect(PlanMatrix.rankOf(PlanMatrix.anonymousKey), 0);
      expect(PlanMatrix.rankOf(PlanMatrix.freeKey), 1);
      for (final level in PlanMatrix.levels) {
        expect(PlanMatrix.rankOf(level.id), greaterThan(1));
      }
    });

    test('palier inconnu → quota 0 (fail-closed, jamais illimité)', () {
      for (final quota in PlanQuota.values) {
        expect(PlanMatrix.quotaLimit('quantum', quota), 0);
      }
      expect(PlanMatrix.rankOf('quantum'), 0);
      expect(PlanMatrix.isPurchasable('quantum'), isFalse);
    });

    test(
      'entitlement RevenueCat "Bailan Pro" (typo historique) résout vers pro',
      () {
        // R4 : cette chaîne est la clé effective des abonnés existants. La
        // « corriger » ferait ignorer silencieusement TOUS leurs events.
        expect(PlanMatrix.levelForRcEntitlement('Bailan Pro'), 'pro');
        expect(PlanMatrix.levelForRcEntitlement('Baillan Pro'), isNull);
        expect(PlanMatrix.levelForRcEntitlement('inconnu'), isNull);
      },
    );

    test(
      'une feature "planned" est refusée à TOUS les paliers, Ultra inclus',
      () {
        final top = PlanMatrix.levels.last.id;
        for (final feature in PlanFeature.values) {
          if (PlanMatrix.isFeatureShipped(feature)) continue;
          expect(
            PlanMatrix.hasFeature(top, feature),
            isFalse,
            reason:
                '${feature.id} est annoncée mais non construite : la promettre '
                'au palier le plus élevé serait un bug commercial.',
          );
        }
      },
    );

    test('hasFeature suit le rang pour une feature livrée', () {
      for (final feature in PlanFeature.values) {
        if (!PlanMatrix.isFeatureShipped(feature)) continue;
        final min = PlanMatrix.minLevelFor(feature);
        expect(PlanMatrix.hasFeature(min, feature), isTrue);
        expect(PlanMatrix.hasFeature(PlanMatrix.freeKey, feature), isFalse);
        expect(
          PlanMatrix.hasFeature(PlanMatrix.anonymousKey, feature),
          isFalse,
        );
      }
    });

    test('un palier vendable a toujours un entitlement RevenueCat', () {
      for (final level in PlanMatrix.levels) {
        if (!level.purchasable) continue;
        expect(
          level.rcEntitlementId,
          isNotNull,
          reason:
              '${level.id} est vendable sans entitlement RC : on encaisserait '
              "sans jamais accorder l'accès.",
        );
      }
    });

    test('minLevelForQuota rend le plus petit palier suffisant', () {
      // documentMaxBytes est le seul quota borné côté payant : 10 Mio (pro),
      // au-delà il faut monter. Le test reste vrai si la grille change : on
      // vérifie la PROPRIÉTÉ (minimalité), pas des valeurs codées en dur.
      const quota = PlanQuota.documentMaxBytes;
      for (final level in PlanMatrix.levels) {
        final limit = PlanMatrix.quotaLimit(level.id, quota);
        if (limit == null) continue;
        final resolved = PlanMatrix.minLevelForQuota(quota, limit);
        expect(resolved, isNotNull);
        expect(
          PlanMatrix.rankOf(resolved!),
          lessThanOrEqualTo(PlanMatrix.rankOf(level.id)),
        );
      }
      // Au-delà du plafond du palier le plus élevé : aucun upsell possible.
      final top = PlanMatrix.levels.last.id;
      final topLimit = PlanMatrix.quotaLimit(top, quota);
      if (topLimit != null) {
        expect(PlanMatrix.minLevelForQuota(quota, topLimit + 1), isNull);
      }
    });
  });
}

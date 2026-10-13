/// Tests de [PlanEntitlement] — droits effectifs dérivés de la table générée
/// (FEAT-056 §1.5).
library;

import 'package:easyrent/features/auth/domain/plan_entitlement.dart';
import 'package:easyrent/features/auth/domain/plan_level.dart';
import 'package:easyrent/features/auth/domain/plan_matrix.g.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:flutter_test/flutter_test.dart';

const _anonymous = PlanEntitlement(tier: SubscriptionTier.anonymous);
const _free = PlanEntitlement(tier: SubscriptionTier.free);
const _pro = PlanEntitlement(tier: SubscriptionTier.paid, level: PlanLevel.pro);
const _max = PlanEntitlement(tier: SubscriptionTier.paid, level: PlanLevel.max);
const _ultra = PlanEntitlement(
  tier: SubscriptionTier.paid,
  level: PlanLevel.ultra,
);

void main() {
  test(
    'level non-null SSI tier == paid (invariant I1, garde en constructeur)',
    () {
      expect(
        () =>
            PlanEntitlement(tier: SubscriptionTier.free, level: PlanLevel.pro),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PlanEntitlement(tier: SubscriptionTier.paid),
        throwsA(isA<AssertionError>()),
      );
    },
  );

  group(
    'rank — ordre total croissant anonymous < free < pro < max < ultra',
    () {
      test('rangs strictement croissants', () {
        expect(_anonymous.rank, lessThan(_free.rank));
        expect(_free.rank, lessThan(_pro.rank));
        expect(_pro.rank, lessThan(_max.rank));
        expect(_max.rank, lessThan(_ultra.rank));
      });
    },
  );

  group('atLeast — les 5 combinaisons de rang', () {
    test('anonymous n\'atteint aucun palier payant', () {
      expect(_anonymous.atLeast(PlanLevel.pro), isFalse);
      expect(_anonymous.atLeast(PlanLevel.max), isFalse);
      expect(_anonymous.atLeast(PlanLevel.ultra), isFalse);
    });

    test('free n\'atteint aucun palier payant', () {
      expect(_free.atLeast(PlanLevel.pro), isFalse);
      expect(_free.atLeast(PlanLevel.max), isFalse);
      expect(_free.atLeast(PlanLevel.ultra), isFalse);
    });

    test('pro atteint pro seulement', () {
      expect(_pro.atLeast(PlanLevel.pro), isTrue);
      expect(_pro.atLeast(PlanLevel.max), isFalse);
      expect(_pro.atLeast(PlanLevel.ultra), isFalse);
    });

    test('max atteint pro et max, pas ultra', () {
      expect(_max.atLeast(PlanLevel.pro), isTrue);
      expect(_max.atLeast(PlanLevel.max), isTrue);
      expect(_max.atLeast(PlanLevel.ultra), isFalse);
    });

    test('ultra atteint les trois paliers payants', () {
      expect(_ultra.atLeast(PlanLevel.pro), isTrue);
      expect(_ultra.atLeast(PlanLevel.max), isTrue);
      expect(_ultra.atLeast(PlanLevel.ultra), isTrue);
    });
  });

  group('quota — illimité vs borné, valeurs actuelles préservées', () {
    test(
      'free : plafonds actuels (2 biens / 3 locataires / 2 baux / 10 docs / 3 scénarios)',
      () {
        expect(_free.quota(PlanQuota.properties), 2);
        expect(_free.quota(PlanQuota.tenants), 3);
        expect(_free.quota(PlanQuota.activeLeases), 2);
        expect(_free.quota(PlanQuota.documents), 10);
        expect(_free.quota(PlanQuota.scenarios), 3);
      },
    );

    test('anonymous : plafonds actuels (0 partout sauf 1 scénario)', () {
      expect(_anonymous.quota(PlanQuota.properties), 0);
      expect(_anonymous.quota(PlanQuota.tenants), 0);
      expect(_anonymous.quota(PlanQuota.activeLeases), 0);
      expect(_anonymous.quota(PlanQuota.documents), 0);
      expect(_anonymous.quota(PlanQuota.scenarios), 1);
    });

    // Grille resserrée FEAT-056 §2 (docs/backlog/056-abonnements-pro-max-ultra.md) :
    // Pro et Max ont désormais des plafonds de volume différenciés (« payant »
    // n'est plus synonyme d'« illimité » dès Pro) ; seul Ultra reste illimité
    // sur tous les axes de comptage.
    test(
      'pro : plafonds intermédiaires (5 biens / 8 locataires / 5 baux / 50 docs / 15 scénarios)',
      () {
        expect(_pro.quota(PlanQuota.properties), 5);
        expect(_pro.quota(PlanQuota.tenants), 8);
        expect(_pro.quota(PlanQuota.activeLeases), 5);
        expect(_pro.quota(PlanQuota.documents), 50);
        expect(_pro.quota(PlanQuota.scenarios), 15);
      },
    );

    test(
      'max : plafonds plus larges (15 biens / 20 locataires / 15 baux / 150 docs / 30 scénarios)',
      () {
        expect(_max.quota(PlanQuota.properties), 15);
        expect(_max.quota(PlanQuota.tenants), 20);
        expect(_max.quota(PlanQuota.activeLeases), 15);
        expect(_max.quota(PlanQuota.documents), 150);
        expect(_max.quota(PlanQuota.scenarios), 30);
      },
    );

    test('ultra : illimité sur tous les quotas de comptage', () {
      expect(_ultra.quota(PlanQuota.properties), isNull);
      expect(_ultra.quota(PlanQuota.tenants), isNull);
      expect(_ultra.quota(PlanQuota.activeLeases), isNull);
      expect(_ultra.quota(PlanQuota.documents), isNull);
      expect(_ultra.quota(PlanQuota.scenarios), isNull);
    });
  });

  group('has — dérivé de minLevel, jamais de comparaison d\'index d\'enum', () {
    test('chargeRegularization/scenarioComparison : dès Pro', () {
      for (final feature in [
        PlanFeature.chargeRegularization,
        PlanFeature.scenarioComparison,
      ]) {
        expect(_anonymous.has(feature), isFalse);
        expect(_free.has(feature), isFalse);
        expect(_pro.has(feature), isTrue);
        expect(_max.has(feature), isTrue);
        expect(_ultra.has(feature), isTrue);
      }
    });

    test('feature "planned" refusée à tous les paliers, Ultra inclus', () {
      // accountingExport : minLevel ultra, status planned au moment du plan.
      expect(_ultra.has(PlanFeature.accountingExport), isFalse);
    });
  });

  group('PlanEntitlement.fromRaw', () {
    test('compte paid legacy (raw null) → pro, atLeast(pro) vrai', () {
      final plan = PlanEntitlement.fromRaw(tier: SubscriptionTier.paid);
      expect(plan.level, PlanLevel.pro);
      expect(plan.atLeast(PlanLevel.pro), isTrue);
    });

    test('compte free → level null, atLeast(pro) faux', () {
      final plan = PlanEntitlement.fromRaw(
        tier: SubscriptionTier.free,
        rawPlanLevel: 'pro',
      );
      expect(plan.level, isNull);
      expect(plan.atLeast(PlanLevel.pro), isFalse);
    });
  });
}

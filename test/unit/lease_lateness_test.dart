/// Tests unitaires de [isLeaseLate] (FEAT-028).
///
/// Couvre les scénarios Gherkin de `docs/backlog/028-retards-paiement.md`
/// ainsi que les cas limites de proratisation, clamp de fin de mois et
/// délai de grâce.
///
/// Convention des dates de test : sauf mention contraire, `startDate` est
/// choisie pour qu'il n'existe qu'UN SEUL mois dû entre le démarrage du bail
/// et `now` — cela isole strictement le comportement testé (délai de grâce,
/// couverture d'un paiement, clamp de fin de mois) d'un éventuel retard
/// accumulé sur des mois antérieurs, qui est testé séparément dans le
/// groupe « multi-mois ».
library;

import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  String id = 'l1',
  LeaseStatus status = LeaseStatus.active,
  required DateTime startDate,
  DateTime? endDate,
  int paymentDay = 1,
}) => Lease(
  id: id,
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: startDate,
  endDate: endDate,
  status: status,
  leaseType: LeaseType.unfurnished,
  paymentDay: paymentDay,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Payment _makePayment({
  String id = 'pay1',
  required DateTime periodStart,
  required DateTime periodEnd,
  DateTime? paidAt,
}) => Payment(
  id: id,
  leaseId: 'l1',
  landlordId: 'owner',
  periodStart: periodStart,
  periodEnd: periodEnd,
  paidAt: paidAt ?? periodStart,
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('isLeaseLate — scénarios Gherkin (docs/backlog/028)', () {
    test('bail récent, 1ʳᵉ échéance dépassée + grâce écoulée, aucun paiement '
        '→ true', () {
      // Bail démarré il y a 20 jours (14 juin), paymentDay=1 : l'ancienne
      // règle (fetchRetards startDate <= now-35j) l'aurait ignoré à tort —
      // c'est le bug corrigé par cette feature.
      // Mois de démarrage = juin. Échéance(juin, day=1) = 1er juin, AVANT
      // le 14 juin (jour de démarrage) → on saute à juillet. Échéance
      // (juillet) = 1er juillet, qui est bien après le 14 juin → 1ʳᵉ
      // échéance due = 1er juillet. now = 10 juillet → 9 jours après,
      // hors délai de grâce (5j) → juillet est le seul mois dû → true.
      final lease = _makeLease(startDate: DateTime(2026, 6, 14), paymentDay: 1);
      final now = DateTime(2026, 7, 10);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });

    test('bail payé pour le mois en cours → false', () {
      // Démarre le 1er juin, paymentDay=5 : échéance(juin)=5 juin >= 1er
      // juin → juin est le 1ʳᵉ mois éligible. now = 10 juin → seul juin est
      // en jeu (hors grâce, 5j après le 5 juin). Payé intégralement → false.
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 5);
      final now = DateTime(2026, 6, 10);
      final payment = _makePayment(
        periodStart: DateTime(2026, 6, 1),
        periodEnd: DateTime(2026, 6, 30),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });

    test(
      'échéance dépassée mais dans le délai de grâce (J+3 < 5j) → false',
      () {
        // Démarre le 1er juin, paymentDay=1 : juin est le seul mois en jeu.
        // now = 4 juin → 3 jours après l'échéance du 1er, < 5j de grâce.
        final lease = _makeLease(
          startDate: DateTime(2026, 6, 1),
          paymentDay: 1,
        );
        final now = DateTime(2026, 6, 4);

        final result = isLeaseLate(lease: lease, payments: const [], now: now);
        expect(result, isFalse);
      },
    );

    test('échéance dépassée au-delà du délai de grâce (J+6 > 5j) → true', () {
      // Démarre le 1er juin, paymentDay=1. now = 7 juin → 6 jours après
      // l'échéance du 1er, > 5j de grâce → juin est dû et impayé.
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 1);
      final now = DateTime(2026, 6, 7);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });

    test('bail terminé → jamais en retard, même sans paiement récent', () {
      final lease = _makeLease(
        status: LeaseStatus.terminated,
        startDate: DateTime(2020, 1, 1),
        paymentDay: 1,
      );
      final now = DateTime(2026, 7, 10);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isFalse);
    });

    test('bail archivé → jamais en retard (même règle que terminated)', () {
      final lease = _makeLease(
        status: LeaseStatus.archived,
        startDate: DateTime(2020, 1, 1),
        paymentDay: 1,
      );
      final now = DateTime(2026, 7, 10);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isFalse);
    });

    test('paiement en avance couvrant le mois dû en entier → false', () {
      // Démarre le 1er juin, paymentDay=1 : juin est le seul mois en jeu.
      // Paiement fait le 28 mai (paidAt), période couvrant juin en entier.
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 1);
      final now = DateTime(2026, 6, 10);
      final payment = _makePayment(
        periodStart: DateTime(2026, 6, 1),
        periodEnd: DateTime(2026, 6, 30),
        paidAt: DateTime(2026, 5, 28),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });

    test('bail démarrant en cours de mois (15 mars, paymentDay=1) → pas de '
        'fausse alerte sur le mois de signature', () {
      // Démarre le 15 mars. Échéance(mars, day=1) = 1er mars, AVANT le 15
      // mars → on saute à avril (1er avril >= 15 mars). 1ʳᵉ échéance due =
      // 1er avril. now = 20 mars (5 jours après démarrage, bien avant même
      // l'échéance d'avril) → aucun mois dû → false.
      final lease = _makeLease(startDate: DateTime(2026, 3, 15), paymentDay: 1);
      final now = DateTime(2026, 3, 20);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isFalse);
    });

    test('bail en retard ET renouvelable (endDate proche) → isLeaseLate reste '
        'vrai (pure lateness check, indépendant de endDate — la priorité '
        "d'affichage late > renewable est arbitrée par lease_status_mapper, "
        'pas par cette fonction)', () {
      final lease = _makeLease(
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 7, 20), // dans <60j de `now`
        paymentDay: 1,
      );
      final now = DateTime(2026, 6, 10);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });
  });

  group('isLeaseLate — clamp fin de mois (paymentDay=31)', () {
    test('paymentDay=31 sur mois court (février non bissextile) → échéance '
        'clampée au 28, dû au-delà de la grâce', () {
      // Démarre le 1er février 2026 (non bissextile), paymentDay=31 →
      // échéance(février) = 28 février (clamp) >= 1er février → février
      // est le seul mois en jeu.
      final lease = _makeLease(startDate: DateTime(2026, 2, 1), paymentDay: 31);
      // Grâce 5j → deadline = 5 mars. now = 6 mars → hors grâce → dû.
      final now = DateTime(2026, 3, 6);

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });

    test('paymentDay=31, paiement couvrant exactement le mois court (28/02) '
        '→ false', () {
      final lease = _makeLease(startDate: DateTime(2026, 2, 1), paymentDay: 31);
      final now = DateTime(2026, 3, 6);
      final payment = _makePayment(
        periodStart: DateTime(2026, 2, 1),
        periodEnd: DateTime(2026, 2, 28),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });

    test('paymentDay=31 sur année bissextile (2028) → échéance clampée au 29 '
        'février, paiement couvrant jusqu\'au 29 seulement → false', () {
      final lease = _makeLease(startDate: DateTime(2028, 2, 1), paymentDay: 31);
      final now = DateTime(2028, 3, 6);
      final payment = _makePayment(
        periodStart: DateTime(2028, 2, 1),
        periodEnd: DateTime(2028, 2, 29),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });

    test('paymentDay=31 sur année bissextile (2028), paiement s\'arrêtant '
        'avant le début du mois → true (aucune intersection, pas de '
        'recouvrement)', () {
      final lease = _makeLease(startDate: DateTime(2028, 2, 1), paymentDay: 31);
      final now = DateTime(2028, 3, 6);
      // Paiement pour janvier uniquement : periodEnd (31 janvier) est
      // AVANT le premier jour de février → pas de recouvrement du tout.
      final payment = _makePayment(
        periodStart: DateTime(2028, 1, 1),
        periodEnd: DateTime(2028, 1, 31),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isTrue);
    });
  });

  group('isLeaseLate — proratisation du mois de démarrage', () {
    test('paymentDay > jour de démarrage dans le même mois → 1ʳᵉ échéance due '
        'est le mois de démarrage lui-même (pas de saut)', () {
      // Démarre le 5 mars, paymentDay=20 : échéance(mars, day=20) = 20
      // mars, qui est APRÈS le 5 mars → pas de saut, mars est éligible.
      final lease = _makeLease(startDate: DateTime(2026, 3, 5), paymentDay: 20);
      final now = DateTime(2026, 3, 26); // 6 jours après le 20 mars

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });

    test('paymentDay == jour de démarrage exact → échéance du mois de '
        'démarrage est retenue (>= inclusif, pas de saut)', () {
      // Démarre le 10 mars, paymentDay=10 : échéance(mars) = 10 mars,
      // égale au jour de démarrage → "le jour de début du bail ou après"
      // → retenue, pas de saut au mois suivant.
      final lease = _makeLease(
        startDate: DateTime(2026, 3, 10),
        paymentDay: 10,
      );
      final now = DateTime(2026, 3, 16); // 6 jours après le 10 mars

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isTrue);
    });

    test('bail sans aucun paiement, encore dans le délai de grâce → false', () {
      final lease = _makeLease(startDate: DateTime(2026, 7, 1), paymentDay: 1);
      final now = DateTime(2026, 7, 3); // 2 jours après le démarrage/échéance

      final result = isLeaseLate(lease: lease, payments: const [], now: now);
      expect(result, isFalse);
    });
  });

  group('isLeaseLate — couverture multi-mois et multi-paiements', () {
    test('paiement multi-mois couvrant plusieurs mois dus → aucun des mois '
        'couverts n\'est en retard', () {
      final lease = _makeLease(startDate: DateTime(2026, 1, 1), paymentDay: 1);
      final now = DateTime(2026, 3, 10); // mois dû courant = mars
      final payment = _makePayment(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 3, 31),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });

    test(
      'paiement qui couvre un mois passé mais PAS le mois dû courant → true',
      () {
        final lease = _makeLease(
          startDate: DateTime(2026, 1, 1),
          paymentDay: 1,
        );
        final now = DateTime(2026, 3, 10); // mois dû courant = mars
        // Paiement pour janvier uniquement — mars reste impayé.
        final payment = _makePayment(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
        );

        final result = isLeaseLate(lease: lease, payments: [payment], now: now);
        expect(result, isTrue);
      },
    );

    test('plusieurs paiements dont un seul couvre le mois dû → false (pas '
        'besoin d\'union, un seul suffit)', () {
      final lease = _makeLease(startDate: DateTime(2026, 1, 1), paymentDay: 1);
      final now = DateTime(2026, 3, 10); // mois dû courant = mars
      final payments = [
        _makePayment(
          id: 'p1',
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
        ),
        _makePayment(
          id: 'p2',
          periodStart: DateTime(2026, 3, 1),
          periodEnd: DateTime(2026, 3, 31),
        ),
      ];

      final result = isLeaseLate(lease: lease, payments: payments, now: now);
      expect(result, isFalse);
    });

    test('paiement partiel de période (chevauche seulement le début du mois) '
        '→ considéré comme couvrant (recouvrement d\'intervalle, pas de '
        'vérification de montant — limite connue documentée hors scope)', () {
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 1);
      final now = DateTime(2026, 6, 10);
      // Période ne couvrant que les 5 premiers jours de juin — recouvre
      // quand même le mois par définition (au moins un jour d'intersection).
      final payment = _makePayment(
        periodStart: DateTime(2026, 6, 1),
        periodEnd: DateTime(2026, 6, 5),
      );

      final result = isLeaseLate(lease: lease, payments: [payment], now: now);
      expect(result, isFalse);
    });
  });

  group('isLeaseLate — graceDays personnalisé (bornes)', () {
    test('graceDays=0 → dû dès le lendemain de l\'échéance', () {
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 1);
      final now = DateTime(2026, 6, 2); // 1 jour après l'échéance

      final result = isLeaseLate(
        lease: lease,
        payments: const [],
        now: now,
        graceDays: 0,
      );
      expect(result, isTrue);
    });

    test('graceDays=0 — le jour même de l\'échéance est déjà en retard '
        '(règle inclusive : échéance + grâce <= now)', () {
      final lease = _makeLease(startDate: DateTime(2026, 6, 1), paymentDay: 1);
      final now = DateTime(2026, 6, 1); // jour même de l'échéance

      final result = isLeaseLate(
        lease: lease,
        payments: const [],
        now: now,
        graceDays: 0,
      );
      expect(result, isTrue);
    });

    test(
      'graceDays=0 — la veille de l\'échéance n\'est pas encore en retard',
      () {
        final lease = _makeLease(
          startDate: DateTime(2026, 6, 1),
          paymentDay: 1,
        );
        final now = DateTime(2026, 5, 31); // veille de l'échéance du 1er juin

        final result = isLeaseLate(
          lease: lease,
          payments: const [],
          now: now,
          graceDays: 0,
        );
        expect(result, isFalse);
      },
    );
  });

  group(
    'isLeaseLate — invariant round-trip UTC (régression fuseau horaire)',
    () {
      // En chaîne de prod, `startDate`/`periodStart`/`periodEnd` sont écrits
      // `.toUtc().toIso8601String()` puis relus par `firestoreDocToSnakeJson`
      // (`Timestamp.toDate().toUtc().toIso8601String()`,
      // cf. core/firestore_helpers.dart) : `DateTime.parse` sur cette chaîne
      // suffixée `Z` renvoie un `DateTime` UTC, PAS local. Si `_dateOnly`
      // tronque directement cet instant UTC sans repasser par `.toLocal()`
      // au préalable, le jour lu est le jour UTC — décalé de −1 jour par
      // rapport au calendrier civil français (Europe/Paris, UTC+1/+2) selon
      // l'heure de la journée où la date a été enregistrée.
      //
      // Ce test simule exactement ce round-trip (`DateTime.parse` d'une
      // chaîne `.toUtc().toIso8601String()`) et vérifie l'INVARIANT que la
      // fonction doit respecter : le verdict de `isLeaseLate` ne doit PAS
      // dépendre de la forme (locale vs UTC-round-trippée) sous laquelle la
      // même date civile lui est passée — sinon deux appelants qui
      // persistent/relisent la même donnée obtiendraient des résultats
      // incohérents selon le fuseau d'exécution du runner.
      //
      // Cas-bord reproduisant le bug signalé en review : bail démarrant le
      // 16 juin, paymentDay=15 (paymentDay <= jour de démarrage → l'échéance
      // de juin, le 15, est AVANT le 16 → on doit sauter à juillet). now =
      // 21 juin : juin n'est pas encore éligible, juillet n'est pas encore
      // atteint → aucun mois dû → attendu `false` dans les DEUX formes.
      // Avant le fix, sous un offset UTC ≠ 0 côté runner, la forme
      // UTC-round-trippée de `startDate` pouvait lire "15 juin" au lieu de
      // "16 juin" → paymentDay(15) devenait `>=` jour lu(15) → juin retenu à
      // tort comme mois éligible → `true` au lieu de `false` (divergence
      // avec la forme locale, qui reste correcte). Ce test échoue AVANT le
      // fix de `_dateOnly` (sous un offset ≠ 0, ex. Europe/Paris) et passe
      // après.
      DateTime roundTripUtc(DateTime local) =>
          DateTime.parse(local.toUtc().toIso8601String());

      test(
        'bail démarrant le 16 juin, paymentDay=15, now=21 juin → false '
        'IDENTIQUE que startDate soit passé en forme locale ou '
        'UTC-round-trippée (round-trip .toUtc().toIso8601String() → parse)',
        () {
          final startDateLocal = DateTime(2026, 6, 16);
          final startDateRoundTripped = roundTripUtc(startDateLocal);
          final now = DateTime(2026, 6, 21);

          final resultLocal = isLeaseLate(
            lease: _makeLease(startDate: startDateLocal, paymentDay: 15),
            payments: const [],
            now: now,
          );
          final resultRoundTripped = isLeaseLate(
            lease: _makeLease(startDate: startDateRoundTripped, paymentDay: 15),
            payments: const [],
            now: now,
          );

          expect(
            resultRoundTripped,
            resultLocal,
            reason:
                'Le verdict ne doit pas dépendre de la forme (locale vs '
                'UTC-round-trippée) sous laquelle startDate est fourni.',
          );
          expect(resultLocal, isFalse);
          expect(resultRoundTripped, isFalse);
        },
      );

      test('même invariant sur `now` : now passé en forme UTC-round-trippée '
          'donne le même verdict que now en forme locale', () {
        final startDate = DateTime(2026, 6, 16);
        final nowLocal = DateTime(2026, 6, 21);
        final nowRoundTripped = roundTripUtc(nowLocal);

        final resultLocal = isLeaseLate(
          lease: _makeLease(startDate: startDate, paymentDay: 15),
          payments: const [],
          now: nowLocal,
        );
        final resultRoundTripped = isLeaseLate(
          lease: _makeLease(startDate: startDate, paymentDay: 15),
          payments: const [],
          now: nowRoundTripped,
        );

        expect(resultRoundTripped, resultLocal);
        expect(resultLocal, isFalse);
      });

      test('invariant symétrique sur un cas → true : bail démarrant le 1er '
          'janvier, paymentDay=1, now=10 juillet, aucun paiement → true dans '
          'les deux formes (periodStart/periodEnd round-trippés inclus)', () {
        final startDateLocal = DateTime(2026, 1, 1);
        final nowLocal = DateTime(2026, 7, 10);

        final resultLocal = isLeaseLate(
          lease: _makeLease(startDate: startDateLocal, paymentDay: 1),
          payments: const [],
          now: nowLocal,
        );
        final resultRoundTripped = isLeaseLate(
          lease: _makeLease(
            startDate: roundTripUtc(startDateLocal),
            paymentDay: 1,
          ),
          payments: const [],
          now: roundTripUtc(nowLocal),
        );

        expect(resultRoundTripped, resultLocal);
        expect(resultLocal, isTrue);
      });

      test('invariant sur periodStart/periodEnd d\'un paiement (couverture) : '
          'un paiement couvrant le mois dû en forme locale ou '
          'UTC-round-trippée donne le même verdict de couverture', () {
        final lease = _makeLease(
          startDate: DateTime(2026, 6, 1),
          paymentDay: 1,
        );
        final now = DateTime(2026, 6, 10);
        final periodStartLocal = DateTime(2026, 6, 1);
        final periodEndLocal = DateTime(2026, 6, 30);

        final resultLocal = isLeaseLate(
          lease: lease,
          payments: [
            _makePayment(
              periodStart: periodStartLocal,
              periodEnd: periodEndLocal,
            ),
          ],
          now: now,
        );
        final resultRoundTripped = isLeaseLate(
          lease: lease,
          payments: [
            _makePayment(
              periodStart: roundTripUtc(periodStartLocal),
              periodEnd: roundTripUtc(periodEndLocal),
            ),
          ],
          now: now,
        );

        expect(resultRoundTripped, resultLocal);
        expect(resultLocal, isFalse);
      });
    },
  );
}

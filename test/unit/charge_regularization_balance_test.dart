/// Tests de [ChargeRegularizationBalance] (FEAT-029 V1.2).
///
/// Couvre :
/// - calcul du solde signé (dépenses réelles − provisions)
/// - sens du solde (positif = à réclamer, négatif = à rembourser, zéro =
///   équilibré) et libellé français explicite associé
/// - `balanceAbsCents` toujours positif quel que soit le signe du solde
///
/// ⚠️ Ce test garde volontairement la formule EXPLICITE (`actual - provisions`)
/// en assertion séparée du getter, pour détecter une inversion accidentelle
/// du signe (risque identifié dans le cahier des charges — un solde inversé
/// exposerait à réclamer au locataire alors qu'un remboursement est dû).
///
/// Étend également la couverture FEAT-036 (non-régression AC-2) : un bail
/// avec `nonRecoverableChargesCents > 0` doit produire EXACTEMENT le même
/// solde qu'un bail identique avec 0, car seul `lease.chargesAmountCents`
/// (le récupérable) alimente la chaîne de calcul via les provisions
/// encaissées — voir groupe « FEAT-036 » ci-dessous.
library;

import 'package:easyrent/features/charge_regularization/application/charge_provisions_calculator.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChargeRegularizationBalance.balanceCents — formule', () {
    test('dépenses réelles > provisions → solde positif', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 120000,
        actualExpensesCents: 130000,
      );
      expect(balance.balanceCents, 10000);
      expect(
        balance.balanceCents,
        balance.actualExpensesCents - balance.provisionsCollectedCents,
      );
    });

    test('dépenses réelles < provisions → solde négatif', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 120000,
        actualExpensesCents: 85000,
      );
      expect(balance.balanceCents, -35000);
    });

    test('dépenses réelles == provisions → solde zéro', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 120000,
        actualExpensesCents: 120000,
      );
      expect(balance.balanceCents, 0);
    });

    test('provisions et dépenses toutes deux nulles → solde zéro', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 0,
        actualExpensesCents: 0,
      );
      expect(balance.balanceCents, 0);
      expect(balance.direction, ChargeRegularizationBalanceDirection.balanced);
    });
  });

  group('ChargeRegularizationBalance.direction — sens du solde', () {
    test('solde positif → dueByTenant', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 108500,
      );
      expect(
        balance.direction,
        ChargeRegularizationBalanceDirection.dueByTenant,
      );
    });

    test('solde négatif → dueToTenant', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 91500,
      );
      expect(
        balance.direction,
        ChargeRegularizationBalanceDirection.dueToTenant,
      );
    });

    test('solde zéro → balanced', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 50000,
        actualExpensesCents: 50000,
      );
      expect(balance.direction, ChargeRegularizationBalanceDirection.balanced);
    });
  });

  group('ChargeRegularizationBalance.labelFr — libellé explicite', () {
    test('solde positif → "à réclamer au locataire"', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 108500,
      );
      expect(balance.labelFr, 'à réclamer au locataire');
    });

    test('solde négatif → "à rembourser au locataire"', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 91500,
      );
      expect(balance.labelFr, 'à rembourser au locataire');
    });

    test('solde zéro → "aucun solde"', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 50000,
        actualExpensesCents: 50000,
      );
      expect(balance.labelFr, 'aucun solde');
    });
  });

  group('ChargeRegularizationBalance.balanceAbsCents — valeur absolue', () {
    test('solde positif → balanceAbsCents == balanceCents', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 108500,
      );
      expect(balance.balanceAbsCents, 8500);
      expect(balance.balanceAbsCents, balance.balanceCents);
    });

    test(
      'solde négatif → balanceAbsCents positif (opposé de balanceCents)',
      () {
        final balance = ChargeRegularizationBalance(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          provisionsCollectedCents: 100000,
          actualExpensesCents: 91500,
        );
        expect(balance.balanceCents, -8500);
        expect(balance.balanceAbsCents, 8500);
        expect(balance.balanceAbsCents, greaterThanOrEqualTo(0));
      },
    );

    test('solde zéro → balanceAbsCents == 0', () {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 50000,
        actualExpensesCents: 50000,
      );
      expect(balance.balanceAbsCents, 0);
    });
  });

  group(
    'ChargeRegularizationBalance — non-mélange charges non récupérables',
    () {
      // ⚠️ Rappel légal (docs/backlog/029) : ce modèle ne porte AUCUN champ
      // relatif à `properties.condoFeesNonRecoverableCents` — la classe
      // n'expose que `provisionsCollectedCents` (somme des
      // `payments.chargesAmountCents`) et `actualExpensesCents` (saisie
      // manuelle). Ce test documente l'absence structurelle de ce champ pour
      // qu'une régression future (ajout accidentel d'un champ "non
      // récupérable" dans le solde locataire) soit détectée par une revue de
      // code — un test de compilation ne peut pas vérifier "l'absence d'un
      // champ", donc ce test sert de garde-fou documentaire explicite.
      test('le solde ne dépend que de provisionsCollectedCents et '
          'actualExpensesCents (2 seuls inputs monétaires du modèle)', () {
        final balance = ChargeRegularizationBalance(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          provisionsCollectedCents: 120000,
          actualExpensesCents: 130000,
        );
        expect(
          balance.balanceCents,
          130000 - 120000,
          reason:
              'Le solde doit être calculable uniquement à partir des '
              'provisions récupérables et des dépenses réelles — jamais des '
              'charges non récupérables (rentabilité bailleur).',
        );
      });
    },
  );

  // ---------------------------------------------------------------------------
  // FEAT-036 — non-régression AC-2 : le bail.nonRecoverableChargesCents
  // n'affecte jamais le solde de régularisation.
  //
  // Simule le flux réel de bout en bout (docs/plans/FEAT-036, section d) :
  // lease.chargesAmountCents (récupérable) → pré-remplit
  // payment.chargesAmountCents (comme le fait payment_form_page.dart) →
  // sumChargeProvisionsForPeriod() → provisionsCollectedCents →
  // ChargeRegularizationBalance.balanceCents.
  // ---------------------------------------------------------------------------
  group('FEAT-036 — non-régression : nonRecoverableChargesCents du bail '
      "n'entre jamais dans le solde de régularisation (AC-2)", () {
    Lease buildLease({required int nonRecoverableChargesCents}) => Lease(
      id: 'lease-1',
      landlordId: 'owner-1',
      propertyId: 'prop-1',
      tenantId: 'tenant-1',
      rentAmountCents: 85000,
      chargesAmountCents: 10000, // récupérable — inchangé par le scénario
      nonRecoverableChargesCents: nonRecoverableChargesCents,
      startDate: DateTime(2025, 1, 1),
      status: LeaseStatus.active,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

    /// Simule le pré-remplissage de `payment_form_page.dart` : la
    /// provision de charges du paiement est toujours calquée sur
    /// `lease.chargesAmountCents` (le récupérable), jamais sur
    /// `totalChargesCents` — c'est précisément l'invariant à protéger.
    Payment buildMonthlyPayment(Lease lease, DateTime month) => Payment(
      id: 'payment-${month.month}',
      leaseId: lease.id,
      landlordId: lease.landlordId,
      periodStart: DateTime(month.year, month.month, 1),
      periodEnd: DateTime(month.year, month.month + 1, 0),
      paidAt: DateTime(month.year, month.month, 5),
      rentAmountCents: lease.rentAmountCents,
      chargesAmountCents: lease.chargesAmountCents, // récupérable SEUL
      paymentMethod: PaymentMethod.virement,
      createdAt: month,
      updatedAt: month,
    );

    ChargeRegularizationBalance regularizeYear(
      Lease lease, {
      required int actualExpensesCents,
    }) {
      final periodStart = DateTime(2025, 1, 1);
      final periodEnd = DateTime(2025, 12, 31);
      final payments = List.generate(
        12,
        (i) => buildMonthlyPayment(lease, DateTime(2025, i + 1, 1)),
      );
      final provisionsCollectedCents = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: periodStart,
        referenceEnd: periodEnd,
      );
      return ChargeRegularizationBalance(
        periodStart: periodStart,
        periodEnd: periodEnd,
        provisionsCollectedCents: provisionsCollectedCents,
        actualExpensesCents: actualExpensesCents,
      );
    }

    test('bail SANS non-récupérable (0) — solde de référence', () {
      final lease = buildLease(nonRecoverableChargesCents: 0);
      final balance = regularizeYear(lease, actualExpensesCents: 135000);

      // provisions = 12 * 10000 (récupérable) = 120000
      expect(balance.provisionsCollectedCents, 120000);
      expect(balance.balanceCents, 15000);
    });

    test('bail AVEC non-récupérable > 0 — solde STRICTEMENT IDENTIQUE '
        'au bail à 0 (le non-récupérable est invisible du calcul)', () {
      final leaseWithoutNonRecoverable = buildLease(
        nonRecoverableChargesCents: 0,
      );
      final leaseWithNonRecoverable = buildLease(
        nonRecoverableChargesCents: 4000, // 40 € non récupérable/mois
      );

      final balanceWithout = regularizeYear(
        leaseWithoutNonRecoverable,
        actualExpensesCents: 135000,
      );
      final balanceWith = regularizeYear(
        leaseWithNonRecoverable,
        actualExpensesCents: 135000,
      );

      expect(
        balanceWith.provisionsCollectedCents,
        balanceWithout.provisionsCollectedCents,
        reason:
            'Les provisions encaissées ne doivent dépendre que de '
            'lease.chargesAmountCents (récupérable), jamais de '
            'nonRecoverableChargesCents.',
      );
      expect(
        balanceWith.balanceCents,
        balanceWithout.balanceCents,
        reason:
            'Un bail avec des charges non récupérables > 0 doit '
            'produire EXACTEMENT le même solde de régularisation '
            "qu'un bail identique sans non-récupérable (AC-2) — sinon "
            'le locataire se verrait facturer une charge illégale '
            '(décret n°87-713).',
      );
      expect(balanceWith.direction, balanceWithout.direction);
      expect(balanceWith.labelFr, balanceWithout.labelFr);
    });

    test('le total des charges du bail (totalChargesCents) n\'apparaît '
        'nulle part dans le calcul de provisions', () {
      final lease = buildLease(nonRecoverableChargesCents: 8000);
      final balance = regularizeYear(lease, actualExpensesCents: 120000);

      // Si totalChargesCents (10000 + 8000 = 18000) avait fuité dans le
      // pré-remplissage des paiements, les provisions seraient
      // 12 * 18000 = 216000 au lieu de 12 * 10000 = 120000.
      expect(balance.provisionsCollectedCents, 120000);
      expect(
        balance.provisionsCollectedCents,
        isNot(12 * lease.totalChargesCents),
      );
    });
  });
}

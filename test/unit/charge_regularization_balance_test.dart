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
library;

import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
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
}

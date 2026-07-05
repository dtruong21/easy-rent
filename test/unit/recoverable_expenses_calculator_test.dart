/// Tests de [sumRecoverableExpensesForPeriod] (FEAT-041c).
///
/// Couvre :
/// - somme correcte sur des dépenses récupérables qui recouvrent la période
/// - exclusion des dépenses hors période (avant / après)
/// - recouvrement partiel aux bornes (inclusion totale, pas de proratisation)
/// - exclusion STRICTE des dépenses `non_recoverable` (garde-fou décret
///   87-713), même si leur période recouvre la référence
/// - filtre optionnel par `leaseId`
/// - liste vide → 0 (non-régression V1 : pré-remplissage à 0)
/// - piège de fuseau horaire : comparaison de `DateTime` UTC (tel que relu
///   depuis Firestore) contre une période de référence en heure locale —
///   même piège que `charge_provisions_calculator_test.dart`.
library;

import 'package:easyrent/features/charge_regularization/application/recoverable_expenses_calculator.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Expense _makeExpense({
  String id = 'exp-1',
  String propertyId = 'property-1',
  String? leaseId = 'lease-1',
  required DateTime periodStart,
  required DateTime periodEnd,
  int amountCents = 5000,
  ExpenseCategory category = ExpenseCategory.recoverable,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: propertyId,
  leaseId: leaseId,
  amountCents: amountCents,
  expenseDate: periodStart,
  nature: ExpenseNature.condoCharges,
  category: category,
  periodYear: periodStart.year,
  periodStart: periodStart,
  periodEnd: periodEnd,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('sumRecoverableExpensesForPeriod — cas de base', () {
    test('somme correcte de plusieurs dépenses dans la période', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 1, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'e2',
          periodStart: DateTime(2025, 2, 1),
          periodEnd: DateTime(2025, 2, 28),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 10000);
    });

    test('0 dépense → 0 (non-régression V1 : pré-remplissage à 0)', () {
      final total = sumRecoverableExpensesForPeriod(
        expenses: const [],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group('sumRecoverableExpensesForPeriod — exclusion hors période', () {
    test('dépense entièrement avant la période → exclue', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test('dépense entièrement après la période → exclue', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test('mix dépenses dans/hors période → seules celles dans la période '
        'comptent', () {
      final expenses = [
        _makeExpense(
          id: 'before',
          periodStart: DateTime(2024, 12, 1),
          periodEnd: DateTime(2024, 12, 31),
          amountCents: 9999,
        ),
        _makeExpense(
          id: 'inside',
          periodStart: DateTime(2025, 6, 1),
          periodEnd: DateTime(2025, 6, 30),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'after',
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 2, 28),
          amountCents: 9999,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });
  });

  group('sumRecoverableExpensesForPeriod — recouvrement aux bornes', () {
    test('dépense à cheval sur le début de période → incluse en totalité '
        '(pas de proratisation)', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 12, 15),
          periodEnd: DateTime(2025, 1, 15),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('dépense à cheval sur la fin de période → incluse en totalité', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2025, 12, 15),
          periodEnd: DateTime(2026, 1, 15),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('dépense exactement égale à la période de référence → incluse', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          amountCents: 12000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 12000);
    });

    test('periodEnd de la dépense == referenceStart (1 jour de '
        'recouvrement) → incluse', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 12, 1),
          periodEnd: DateTime(2025, 1, 1),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('periodStart de la dépense == referenceEnd + 1 jour → exclue '
        '(aucun recouvrement)', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group(
    'sumRecoverableExpensesForPeriod — exclusion STRICTE des non_recoverable '
    '(garde-fou décret 87-713)',
    () {
      test('dépense non-récupérable dans la période → EXCLUE malgré le '
          'recouvrement', () {
        final expenses = [
          _makeExpense(
            periodStart: DateTime(2025, 6, 1),
            periodEnd: DateTime(2025, 6, 30),
            amountCents: 99900,
            category: ExpenseCategory.nonRecoverable,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        expect(total, 0);
      });

      test('mix récupérable + non-récupérable → seule la part récupérable '
          'compte', () {
        final expenses = [
          _makeExpense(
            id: 'recoverable',
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 5000,
          ),
          _makeExpense(
            id: 'non-recoverable',
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 999900,
            category: ExpenseCategory.nonRecoverable,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        expect(total, 5000);
      });
    },
  );

  group('sumRecoverableExpensesForPeriod — filtre optionnel leaseId', () {
    test('leaseId fourni → seules les dépenses de ce bail comptent', () {
      final expenses = [
        _makeExpense(
          id: 'lease-a',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'lease-b',
          leaseId: 'lease-b',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 7000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
        leaseId: 'lease-a',
      );
      expect(total, 5000);
    });

    test('leaseId null (défaut) → toutes les dépenses récupérables comptent, '
        'y compris celles sans bail rattaché', () {
      final expenses = [
        _makeExpense(
          id: 'with-lease',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'no-lease',
          leaseId: null,
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 7000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 12000);
    });

    test('leaseId fourni ne correspondant à aucune dépense → 0', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
        leaseId: 'lease-unknown',
      );
      expect(total, 0);
    });
  });

  group('sumRecoverableExpensesForPeriod — dépense récupérable sans période '
      '(défensif)', () {
    test('periodStart/periodEnd null → exclue sans lever d\'exception', () {
      final expense = Expense(
        id: 'no-period',
        landlordId: 'landlord-1',
        propertyId: 'property-1',
        leaseId: 'lease-1',
        amountCents: 5000,
        expenseDate: DateTime(2025, 3, 15),
        nature: ExpenseNature.condoCharges,
        category: ExpenseCategory.recoverable,
        periodYear: 2025,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final total = sumRecoverableExpensesForPeriod(
        expenses: [expense],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group(
    'sumRecoverableExpensesForPeriod — invariant round-trip UTC (régression '
    'fuseau horaire, même pattern que charge_provisions_calculator_test.dart)',
    () {
      // En chaîne de prod, `periodStart`/`periodEnd` d'une [Expense] relue
      // depuis Firestore sont écrits `.toUtc().toIso8601String()` puis
      // reparsés (`firestoreDocToSnakeJson`) — `DateTime.parse` sur cette
      // chaîne suffixée `Z` renvoie un `DateTime` UTC, pas local. Ce test
      // vérifie l'INVARIANT que la fonction doit respecter : le total
      // calculé ne doit PAS dépendre de la forme (locale vs
      // UTC-round-trippée) sous laquelle la même date civile est passée.
      DateTime roundTripUtc(DateTime local) =>
          DateTime.parse(local.toUtc().toIso8601String());

      test('période de dépense UTC-round-trippée donne le MÊME total que la '
          'forme locale équivalente', () {
        final periodStartLocal = DateTime(2025, 1, 1);
        final periodEndLocal = DateTime(2025, 1, 31);

        final expenseLocal = _makeExpense(
          periodStart: periodStartLocal,
          periodEnd: periodEndLocal,
          amountCents: 5000,
        );
        final expenseRoundTripped = _makeExpense(
          periodStart: roundTripUtc(periodStartLocal),
          periodEnd: roundTripUtc(periodEndLocal),
          amountCents: 5000,
        );

        final totalLocal = sumRecoverableExpensesForPeriod(
          expenses: [expenseLocal],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        final totalRoundTripped = sumRecoverableExpensesForPeriod(
          expenses: [expenseRoundTripped],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );

        expect(totalRoundTripped, totalLocal);
        expect(totalRoundTripped, 5000);
      });

      test('référence de période UTC-round-trippée donne le MÊME total que la '
          'forme locale équivalente', () {
        final expense = _makeExpense(
          periodStart: DateTime(2025, 6, 1),
          periodEnd: DateTime(2025, 6, 30),
          amountCents: 7500,
        );

        final totalLocal = sumRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        final totalRoundTripped = sumRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: roundTripUtc(DateTime(2025, 1, 1)),
          referenceEnd: roundTripUtc(DateTime(2025, 12, 31)),
        );

        expect(totalRoundTripped, totalLocal);
        expect(totalRoundTripped, 7500);
      });
    },
  );

  group(
    'sumRecoverableExpensesForPeriod — cas de bord civil fuseau horaire '
    '(correctif review FEAT-041, finding 8 : test probant même sur CI UTC)',
    () {
      // Les tests round-trip ci-dessus ne sont PAS probants sur un runner CI
      // dont le fuseau local est UTC : `toLocal()` y est un no-op, donc le
      // test « passerait » même si l'implémentation oubliait `.toLocal()`
      // (il testerait alors UTC contre UTC, jamais un vrai décalage de jour
      // civil). Ce groupe construit un cas de bord qui bascule de jour civil
      // dans TOUS les fuseaux UTC-négatifs à UTC-positifs plausibles
      // (Amérique jusqu'à Asie) — le test dérive lui-même la date locale
      // attendue via `.toLocal()` sur l'instant UTC testé (l'oracle), plutôt
      // que de coder en dur "1er janvier" qui ne serait vrai qu'en
      // Europe/Paris. Ainsi le test échoue si `_dateOnly` cesse d'appliquer
      // `.toLocal()` avant de tronquer, quel que soit le fuseau du runner.
      test('dépense d\'un seul jour, instant UTC proche de minuit '
          '(2024-12-31T23:00:00Z) rattachée à sa date CIVILE LOCALE, pas à '
          'sa date UTC', () {
        final instantUtc = DateTime.utc(2024, 12, 31, 23);
        expect(
          instantUtc.isUtc,
          isTrue,
          reason:
              'précondition : reproduit un DateTime tel que relu depuis '
              'Firestore (.toUtc().toIso8601String() reparsé)',
        );

        // Oracle : la date civile locale que `_dateOnly` doit produire pour
        // cet instant — recalculée ici avec le MÊME `.toLocal()` que
        // l'implémentation, pas codée en dur, pour rester probante quel
        // que soit le fuseau du runner (UTC sur CI, Europe/Paris en local).
        final localDay = instantUtc.toLocal();
        final expectedLocalDate = DateTime(
          localDay.year,
          localDay.month,
          localDay.day,
        );

        // Dépense d'un SEUL jour (periodStart == periodEnd == le même
        // instant UTC) : indispensable pour que le test soit probant — avec
        // un `periodStart` antérieur distinct, la période de la dépense
        // engloberait la veille ET le jour suivant quel que soit
        // l'arrondi, masquant tout oubli de `.toLocal()`.
        final expense = _makeExpense(
          periodStart: instantUtc,
          periodEnd: instantUtc,
          amountCents: 5000,
        );

        // Référence de période bornée exactement à `expectedLocalDate` :
        // si (et seulement si) l'implémentation tronque bien en date civile
        // LOCALE, la dépense recouvre cette référence d'un jour pile et
        // doit être incluse.
        final totalIncluded = sumRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: expectedLocalDate,
          referenceEnd: expectedLocalDate,
        );
        expect(
          totalIncluded,
          5000,
          reason:
              'la dépense doit recouvrir sa date civile LOCALE dérivée de '
              "l'instant UTC — régression si `_dateOnly` omet `.toLocal()`.",
        );

        // Référence bornée à la veille ET au lendemain de
        // `expectedLocalDate` : une dépense d'un seul jour civil local ne
        // doit recouvrir NI l'un NI l'autre.
        final dayBefore = expectedLocalDate.subtract(const Duration(days: 1));
        final dayAfter = expectedLocalDate.add(const Duration(days: 1));
        expect(
          sumRecoverableExpensesForPeriod(
            expenses: [expense],
            referenceStart: dayBefore,
            referenceEnd: dayBefore,
          ),
          0,
          reason:
              'la veille de la date civile locale ne doit présenter aucun '
              'recouvrement.',
        );
        expect(
          sumRecoverableExpensesForPeriod(
            expenses: [expense],
            referenceStart: dayAfter,
            referenceEnd: dayAfter,
          ),
          0,
          reason:
              'le lendemain de la date civile locale ne doit présenter '
              'aucun recouvrement.',
        );
      });

      test('filterRecoverableExpensesForPeriod applique le même rattachement '
          'civil local que sumRecoverableExpensesForPeriod (cohérence detail '
          '/ total, findings 1 & 7)', () {
        final instantUtc = DateTime.utc(2024, 12, 31, 23);
        final localDay = instantUtc.toLocal();
        final expectedLocalDate = DateTime(
          localDay.year,
          localDay.month,
          localDay.day,
        );

        final expense = _makeExpense(
          periodStart: instantUtc,
          periodEnd: instantUtc,
          amountCents: 5000,
        );

        final filtered = filterRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: expectedLocalDate,
          referenceEnd: expectedLocalDate,
        );
        expect(filtered, hasLength(1));

        final dayBefore = expectedLocalDate.subtract(const Duration(days: 1));
        final filteredExcluded = filterRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: dayBefore,
          referenceEnd: dayBefore,
        );
        expect(filteredExcluded, isEmpty);
      });
    },
  );

  group(
    'expenseAppliesToLease — correctif review FEAT-041 (finding 2, MAJOR)',
    () {
      test('leaseId null (pas de filtre bail) → toujours vrai', () {
        expect(
          expenseAppliesToLease(
            _makeExpense(
              leaseId: 'lease-a',
              periodStart: DateTime(2025, 1, 1),
              periodEnd: DateTime(2025, 1, 31),
            ),
            null,
          ),
          isTrue,
        );
      });

      test('dépense SANS bail (leaseId == null) → INCLUSE pour un bail donné '
          '(cas nominal décompte syndic)', () {
        expect(
          expenseAppliesToLease(
            _makeExpense(
              leaseId: null,
              periodStart: DateTime(2025, 1, 1),
              periodEnd: DateTime(2025, 1, 31),
            ),
            'lease-a',
          ),
          isTrue,
        );
      });

      test('dépense du MÊME bail → INCLUSE', () {
        expect(
          expenseAppliesToLease(
            _makeExpense(
              leaseId: 'lease-a',
              periodStart: DateTime(2025, 1, 1),
              periodEnd: DateTime(2025, 1, 31),
            ),
            'lease-a',
          ),
          isTrue,
        );
      });

      test('dépense d\'un AUTRE bail → EXCLUE', () {
        expect(
          expenseAppliesToLease(
            _makeExpense(
              leaseId: 'lease-b',
              periodStart: DateTime(2025, 1, 1),
              periodEnd: DateTime(2025, 1, 31),
            ),
            'lease-a',
          ),
          isFalse,
        );
      });
    },
  );

  group(
    'sumRecoverableExpensesForPeriod — correctif review FEAT-041 (finding 2, '
    'MAJOR) : dépenses sans bail incluses dans la régularisation d\'un bail',
    () {
      test('dépense récupérable SANS bail, période couvrante, leaseId fourni '
          '→ INCLUSE (cas nominal décompte syndic)', () {
        final expenses = [
          _makeExpense(
            id: 'no-lease',
            leaseId: null,
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 45000,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
          leaseId: 'lease-1',
        );
        expect(total, 45000);
      });

      test('mix dépense sans bail + dépense d\'un AUTRE bail → seule celle '
          'sans bail compte (celle de l\'autre bail est EXCLUE)', () {
        final expenses = [
          _makeExpense(
            id: 'no-lease',
            leaseId: null,
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 45000,
          ),
          _makeExpense(
            id: 'other-lease',
            leaseId: 'lease-other',
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 99900,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
          leaseId: 'lease-1',
        );
        expect(total, 45000);
      });
    },
  );

  group('filterRecoverableExpensesForPeriod — correctif review FEAT-041 '
      '(findings 1 & 7, MAJOR)', () {
    test('ne retient que les dépenses récupérables qui recouvrent la '
        'période (même sémantique que la somme)', () {
      final inside = _makeExpense(
        id: 'inside',
        periodStart: DateTime(2025, 6, 1),
        periodEnd: DateTime(2025, 6, 30),
        amountCents: 5000,
      );
      final outside = _makeExpense(
        id: 'outside',
        periodStart: DateTime(2026, 6, 1),
        periodEnd: DateTime(2026, 6, 30),
        amountCents: 9999,
      );
      final nonRecoverable = _makeExpense(
        id: 'non-recoverable',
        periodStart: DateTime(2025, 6, 1),
        periodEnd: DateTime(2025, 6, 30),
        amountCents: 9999,
        category: ExpenseCategory.nonRecoverable,
      );

      final filtered = filterRecoverableExpensesForPeriod(
        expenses: [inside, outside, nonRecoverable],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );

      expect(filtered.map((e) => e.id), ['inside']);

      final total = sumRecoverableExpensesForPeriod(
        expenses: [inside, outside, nonRecoverable],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(
        total,
        filtered.fold<int>(0, (sum, e) => sum + e.amountCents),
        reason:
            'la somme et la liste filtrée doivent porter EXACTEMENT sur '
            'les mêmes dépenses (correctif findings 1 & 7).',
      );
    });

    test('applique le même filtre leaseId que sumRecoverableExpensesForPeriod '
        '(dépense sans bail incluse, dépense d\'un autre bail exclue)', () {
      final noLease = _makeExpense(
        id: 'no-lease',
        leaseId: null,
        periodStart: DateTime(2025, 3, 1),
        periodEnd: DateTime(2025, 3, 31),
        amountCents: 5000,
      );
      final otherLease = _makeExpense(
        id: 'other-lease',
        leaseId: 'lease-other',
        periodStart: DateTime(2025, 3, 1),
        periodEnd: DateTime(2025, 3, 31),
        amountCents: 9999,
      );
      final sameLease = _makeExpense(
        id: 'same-lease',
        leaseId: 'lease-1',
        periodStart: DateTime(2025, 3, 1),
        periodEnd: DateTime(2025, 3, 31),
        amountCents: 7000,
      );

      final filtered = filterRecoverableExpensesForPeriod(
        expenses: [noLease, otherLease, sameLease],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
        leaseId: 'lease-1',
      );

      expect(filtered.map((e) => e.id).toSet(), {'no-lease', 'same-lease'});
    });
  });
}

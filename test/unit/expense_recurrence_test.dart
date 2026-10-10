/// Tests de `core/finance/expense_recurrence.dart` — calendrier pur de la
/// récurrence virtuelle (FEAT-041d).
///
/// Couvre les trois décisions documentées en tête du module :
/// - expansion mensuelle / trimestrielle / annuelle sur une fenêtre donnée ;
/// - **borne de fin** : `endDate` coupe la série, et une récurrence sans fin
///   s'arrête à la borne haute demandée par l'appelant (jamais de futur) ;
/// - **pas de rétroactivité** : aucune échéance avant la date de la dépense,
///   même si la fenêtre commence plus tôt ;
/// - dépense ponctuelle strictement inchangée.
library;

import 'package:easyrent/core/finance/expense_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseRecurrence — enum', () {
    test('sqlValue / fromSql font l\'aller-retour', () {
      for (final r in ExpenseRecurrence.values) {
        expect(ExpenseRecurrence.fromSql(r.sqlValue), r);
      }
    });

    test('valeur absente ou inconnue → none (dépenses créées avant '
        'FEAT-041d : aucune migration, elles restent ponctuelles)', () {
      expect(ExpenseRecurrence.fromSql(null), ExpenseRecurrence.none);
      expect(ExpenseRecurrence.fromSql('weekly'), ExpenseRecurrence.none);
      expect(ExpenseRecurrence.fromSql(''), ExpenseRecurrence.none);
    });

    test('échéances par an et pas en mois', () {
      expect(ExpenseRecurrence.monthly.occurrencesPerYear, 12);
      expect(ExpenseRecurrence.quarterly.occurrencesPerYear, 4);
      expect(ExpenseRecurrence.yearly.occurrencesPerYear, 1);
      expect(ExpenseRecurrence.none.occurrencesPerYear, 0);

      expect(ExpenseRecurrence.monthly.monthStep, 1);
      expect(ExpenseRecurrence.quarterly.monthStep, 3);
      expect(ExpenseRecurrence.yearly.monthStep, 12);
    });

    test('isRecurring — none exclu, tout le reste inclus', () {
      expect(ExpenseRecurrence.none.isRecurring, isFalse);
      expect(ExpenseRecurrence.monthly.isRecurring, isTrue);
      expect(ExpenseRecurrence.quarterly.isRecurring, isTrue);
      expect(ExpenseRecurrence.yearly.isRecurring, isTrue);
    });
  });

  group('expenseOccurrences — dépense ponctuelle (comportement inchangé)', () {
    test('une seule échéance, à sa date, si elle tombe dans la fenêtre', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 3, 15),
        recurrence: ExpenseRecurrence.none,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, [DateTime(2026, 3, 15)]);
    });

    test('aucune échéance si elle tombe hors de la fenêtre', () {
      expect(
        expenseOccurrences(
          firstOccurrence: DateTime(2025, 3, 15),
          recurrence: ExpenseRecurrence.none,
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        isEmpty,
      );
      expect(
        expenseOccurrences(
          firstOccurrence: DateTime(2027, 3, 15),
          recurrence: ExpenseRecurrence.none,
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        isEmpty,
      );
    });

    test('une date de fin sur une dépense ponctuelle est sans effet', () {
      expect(
        expenseOccurrences(
          firstOccurrence: DateTime(2026, 3, 15),
          recurrence: ExpenseRecurrence.none,
          endDate: DateTime(2026, 1, 1),
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        [DateTime(2026, 3, 15)],
      );
    });
  });

  group('expenseOccurrences — expansion', () {
    test(
      'mensuelle sur une année civile → 12 échéances, même jour du mois',
      () {
        final occurrences = expenseOccurrences(
          firstOccurrence: DateTime(2026, 1, 10),
          recurrence: ExpenseRecurrence.monthly,
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        );

        expect(occurrences, hasLength(12));
        expect(occurrences.first, DateTime(2026, 1, 10));
        expect(occurrences[6], DateTime(2026, 7, 10));
        expect(occurrences.last, DateTime(2026, 12, 10));
      },
    );

    test('trimestrielle sur une année civile → 4 échéances espacées de '
        '3 mois', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 1, 15),
        recurrence: ExpenseRecurrence.quarterly,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, [
        DateTime(2026, 1, 15),
        DateTime(2026, 4, 15),
        DateTime(2026, 7, 15),
        DateTime(2026, 10, 15),
      ]);
    });

    test('annuelle sur 3 ans → 3 échéances', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2024, 9, 1),
        recurrence: ExpenseRecurrence.yearly,
        from: DateTime(2024, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, [
        DateTime(2024, 9, 1),
        DateTime(2025, 9, 1),
        DateTime(2026, 9, 1),
      ]);
    });

    test('le jour est rogné au dernier jour du mois court (31 janvier → '
        '28/29 février), sans sauter ni doubler un mois', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 1, 31),
        recurrence: ExpenseRecurrence.monthly,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 4, 30),
      );

      expect(occurrences, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('le fuseau de la première échéance est préservé (dates Firestore en '
        'UTC)', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime.utc(2026, 1, 10, 8, 30),
        recurrence: ExpenseRecurrence.monthly,
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 3, 31),
      );

      expect(occurrences, hasLength(3));
      expect(occurrences.every((o) => o.isUtc), isTrue);
      expect(occurrences[1], DateTime.utc(2026, 2, 10, 8, 30));
    });

    test('fenêtre inversée (to avant from) → aucune échéance', () {
      expect(
        expenseOccurrences(
          firstOccurrence: DateTime(2026, 1, 1),
          recurrence: ExpenseRecurrence.monthly,
          from: DateTime(2026, 6, 1),
          to: DateTime(2026, 1, 1),
        ),
        isEmpty,
      );
    });
  });

  group('expenseOccurrences — pas de rétroactivité (Décision 2)', () {
    test('une récurrence trimestrielle saisie en septembre ne remplit PAS les '
        'trimestres écoulés avant sa saisie', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 9, 15),
        recurrence: ExpenseRecurrence.quarterly,
        // Fenêtre = toute l'année, y compris avant la saisie.
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      // Septembre puis décembre : les trimestres de janvier, avril et
      // juillet — pourtant dans la fenêtre — restent vides.
      expect(occurrences, [DateTime(2026, 9, 15), DateTime(2026, 12, 15)]);
      expect(
        occurrences.every((o) => !o.isBefore(DateTime(2026, 9, 15))),
        isTrue,
        reason: 'aucune échéance ne doit précéder la date de la dépense',
      );
    });

    test('antidater la dépense reste le moyen — explicite — de couvrir le '
        'passé', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 1, 15), // saisie antidatée
        recurrence: ExpenseRecurrence.quarterly,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, hasLength(4));
    });
  });

  group('expenseOccurrences — borne de fin (Décision 1)', () {
    test('endDate coupe la série (échéance à la date de fin incluse)', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 1, 15),
        recurrence: ExpenseRecurrence.quarterly,
        endDate: DateTime(2026, 7, 15),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, [
        DateTime(2026, 1, 15),
        DateTime(2026, 4, 15),
        DateTime(2026, 7, 15),
      ]);
    });

    test('endDate juste avant une échéance l\'exclut', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2026, 1, 15),
        recurrence: ExpenseRecurrence.quarterly,
        endDate: DateTime(2026, 7, 14),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      expect(occurrences, hasLength(2));
    });

    test('endDate antérieure à la première échéance → aucune échéance', () {
      expect(
        expenseOccurrences(
          firstOccurrence: DateTime(2026, 5, 1),
          recurrence: ExpenseRecurrence.monthly,
          endDate: DateTime(2026, 3, 1),
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31),
        ),
        isEmpty,
      );
    });

    test('récurrence SANS fin → bornée par `to`, jamais projetée au-delà', () {
      final occurrences = expenseOccurrences(
        firstOccurrence: DateTime(2020, 1, 15),
        recurrence: ExpenseRecurrence.monthly,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(occurrences, [
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 15),
        DateTime(2026, 3, 15),
      ]);
    });
  });

  group('isRecurrenceActiveAt', () {
    final now = DateTime(2026, 1, 1);

    test('une dépense ponctuelle n\'est jamais « en cours »', () {
      expect(
        isRecurrenceActiveAt(
          firstOccurrence: DateTime(2025, 1, 1),
          recurrence: ExpenseRecurrence.none,
          at: now,
        ),
        isFalse,
      );
    });

    test('récurrence commencée et sans fin → en cours', () {
      expect(
        isRecurrenceActiveAt(
          firstOccurrence: DateTime(2025, 12, 20),
          recurrence: ExpenseRecurrence.quarterly,
          at: now,
        ),
        isTrue,
      );
    });

    test('récurrence dont la fin est passée → terminée', () {
      expect(
        isRecurrenceActiveAt(
          firstOccurrence: DateTime(2024, 1, 1),
          recurrence: ExpenseRecurrence.monthly,
          endDate: DateTime(2025, 6, 30),
          at: now,
        ),
        isFalse,
      );
    });

    test('récurrence dont la fin est à venir → en cours', () {
      expect(
        isRecurrenceActiveAt(
          firstOccurrence: DateTime(2024, 1, 1),
          recurrence: ExpenseRecurrence.monthly,
          endDate: DateTime(2027, 6, 30),
          at: now,
        ),
        isTrue,
      );
    });

    test('récurrence dont la première échéance est à venir → pas encore en '
        'cours', () {
      expect(
        isRecurrenceActiveAt(
          firstOccurrence: DateTime(2026, 6, 1),
          recurrence: ExpenseRecurrence.yearly,
          at: now,
        ),
        isFalse,
      );
    });
  });
}

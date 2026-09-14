import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // paymentDay=5, grâce 5 j. Bail démarré le 01/01/2026.
  test('mois dû courant = mois précédent quand la deadline est passée', () {
    // now = 20 mars 2026 → l'échéance de mars (5 mars) + grâce (10 mars) est
    // passée → mois dû courant = mars 2026.
    final due = leaseCurrentDueMonth(
      startDate: DateTime(2026, 1, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 20),
    );
    expect(due, isNotNull);
    expect(due!.year, 2026);
    expect(due.month, 3);
  });

  test('null quand aucune échéance n\'est encore due (bail tout neuf)', () {
    final due = leaseCurrentDueMonth(
      startDate: DateTime(2026, 3, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 2), // avant échéance+grâce du 1er mois
    );
    expect(due, isNull);
  });

  test('invariance fuseau : une date UTC-round-trippée donne le même mois', () {
    DateTime rt(DateTime d) => DateTime.parse(d.toUtc().toIso8601String());
    final local = leaseCurrentDueMonth(
      startDate: DateTime(2026, 1, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 20),
    );
    final roundTripped = leaseCurrentDueMonth(
      startDate: rt(DateTime(2026, 1, 1)),
      paymentDay: 5,
      now: rt(DateTime(2026, 3, 20)),
    );
    expect(roundTripped!.month, local!.month);
    expect(roundTripped.year, local.year);
  });
}

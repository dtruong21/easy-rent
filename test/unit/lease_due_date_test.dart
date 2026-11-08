import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('échéance = paymentDay quand le mois est assez long', () {
    expect(
      leaseDueDate(paymentDay: 5, year: 2026, month: 3),
      DateTime(2026, 3, 5),
    );
  });
  test('clamp paymentDay 31 en février (28 j en 2026)', () {
    expect(
      leaseDueDate(paymentDay: 31, year: 2026, month: 2),
      DateTime(2026, 2, 28),
    );
  });
  test('clamp paymentDay 31 en avril (30 j)', () {
    expect(
      leaseDueDate(paymentDay: 31, year: 2026, month: 4),
      DateTime(2026, 4, 30),
    );
  });
}

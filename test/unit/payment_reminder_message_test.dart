import 'package:easyrent/features/leases/domain/payment_reminder_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaymentReminderMessage build() => buildPaymentReminderMessage(
    tenantFirstName: 'Marie',
    landlordFullName: 'Jean Bailleur',
    propertyAddress: '2 rue de Lyon, 69001 Lyon',
    dueMonthLabel: 'septembre 2026',
    amountDueCents: 85000,
  );

  test('sujet mentionne la période', () {
    expect(build().subject, contains('septembre 2026'));
  });

  test('corps mentionne prénom, adresse, montant formaté et signature', () {
    final b = build().body;
    expect(b, contains('Marie'));
    expect(b, contains('2 rue de Lyon, 69001 Lyon'));
    expect(b, contains('850,00')); // MoneyFormat (espace insécable avant €)
    expect(b, contains('Jean Bailleur'));
  });

  test(
    'corps contient la mention légale relance amiable / pas mise en demeure',
    () {
      final b = build().body.toLowerCase();
      expect(b, contains('relance amiable'));
      expect(b, contains('mise en demeure'));
    },
  );
}

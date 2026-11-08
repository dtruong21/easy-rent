import 'package:easyrent/features/leases/domain/payment_reminder_channel.dart';
import 'package:easyrent/features/leases/domain/payment_reminder_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const msg = PaymentReminderMessage(subject: 'Rappel', body: 'Bonjour');

  test('email seul quand pas de téléphone', () {
    expect(availableReminderChannels(phone: null), [ReminderChannel.email]);
    expect(availableReminderChannels(phone: ''), [ReminderChannel.email]);
  });

  test('email + sms + whatsApp pour un mobile FR', () {
    expect(availableReminderChannels(phone: '06 12 34 56 78'), [
      ReminderChannel.email,
      ReminderChannel.sms,
      ReminderChannel.whatsApp,
    ]);
  });

  test(
    'email + sms seulement pour un numéro non-FR (whatsApp indisponible)',
    () {
      expect(availableReminderChannels(phone: '+1 202 555 0100'), [
        ReminderChannel.email,
        ReminderChannel.sms,
      ]);
    },
  );

  test('reminderUriFor email → mailto avec subject+body', () {
    final u = reminderUriFor(
      channel: ReminderChannel.email,
      tenantEmail: 'loc@ex.fr',
      tenantPhone: null,
      message: msg,
    );
    expect(u!.scheme, 'mailto');
    expect(u.path, 'loc@ex.fr');
    expect(u.queryParameters['subject'], 'Rappel');
    expect(u.queryParameters['body'], 'Bonjour');
  });

  test('reminderUriFor whatsApp sur numéro non-FR → null', () {
    final u = reminderUriFor(
      channel: ReminderChannel.whatsApp,
      tenantEmail: 'loc@ex.fr',
      tenantPhone: '+1 202 555 0100',
      message: msg,
    );
    expect(u, isNull);
  });
}

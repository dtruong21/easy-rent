import '../../../core/utils/phone_uri.dart';
import 'payment_reminder_message.dart';

/// Canaux de relance disponibles (FEAT-031 V1).
enum ReminderChannel { email, sms, whatsApp }

bool _hasPhone(String? phone) => phone != null && phone.trim().isNotEmpty;

/// Canaux proposables pour ce locataire : email toujours ; sms si téléphone ;
/// whatsApp seulement si le téléphone est normalisable en FR (cf.
/// [whatsAppUri]).
List<ReminderChannel> availableReminderChannels({required String? phone}) {
  final channels = <ReminderChannel>[ReminderChannel.email];
  if (_hasPhone(phone)) {
    channels.add(ReminderChannel.sms);
    if (whatsAppUri(phone: phone!, text: '') != null) {
      channels.add(ReminderChannel.whatsApp);
    }
  }
  return channels;
}

/// Construit l'URI à ouvrir pour [channel]. `null` si le canal n'est pas
/// exploitable (ex. whatsApp sur numéro non-FR, ou sms/whatsApp sans
/// téléphone) — l'appelant ne devrait proposer que des canaux issus de
/// [availableReminderChannels].
Uri? reminderUriFor({
  required ReminderChannel channel,
  required String tenantEmail,
  required String? tenantPhone,
  required PaymentReminderMessage message,
}) {
  switch (channel) {
    case ReminderChannel.email:
      return Uri(
        scheme: 'mailto',
        path: tenantEmail,
        queryParameters: {'subject': message.subject, 'body': message.body},
      );
    case ReminderChannel.sms:
      if (!_hasPhone(tenantPhone)) return null;
      return smsUri(phone: tenantPhone!, body: message.body);
    case ReminderChannel.whatsApp:
      if (!_hasPhone(tenantPhone)) return null;
      return whatsAppUri(phone: tenantPhone!, text: message.body);
  }
}

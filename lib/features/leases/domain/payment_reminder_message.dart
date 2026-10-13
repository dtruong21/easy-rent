import '../../../core/utils/money_format.dart';

/// Message de relance de paiement pré-rempli (sujet + corps), destiné à être
/// ouvert dans l'app email/SMS/WhatsApp du bailleur (FEAT-031 V1). Contenu
/// métier en français, indépendant de la locale de l'UI.
class PaymentReminderMessage {
  const PaymentReminderMessage({required this.subject, required this.body});

  final String subject;
  final String body;
}

/// Construit le message de relance amiable. Fonction pure, testable.
///
/// Le corps porte OBLIGATOIREMENT la mention « relance amiable » + « ne
/// constitue pas une mise en demeure » (contrainte légale — une mise en
/// demeure exige un acte formel / LRAR, hors périmètre).
PaymentReminderMessage buildPaymentReminderMessage({
  required String tenantFirstName,
  required String landlordFullName,
  required String propertyAddress,
  required String dueMonthLabel,
  required int amountDueCents,
}) {
  final amount = MoneyFormat.formatEurosFromCents(amountDueCents);
  final subject = 'Rappel — loyer de $dueMonthLabel';
  final body =
      'Bonjour $tenantFirstName,\n\n'
      'Sauf erreur de ma part, le loyer de $dueMonthLabel pour le logement '
      'situé $propertyAddress, d\'un montant de $amount, ne m\'apparaît pas '
      'encore réglé.\n\n'
      'Je vous remercie de bien vouloir procéder à sa régularisation. Si le '
      'paiement a déjà été effectué, merci de ne pas tenir compte de ce '
      'message.\n\n'
      'Ceci est une relance amiable et ne constitue pas une mise en demeure.\n\n'
      'Cordialement,\n'
      '$landlordFullName\n\n'
      '---\n'
      'Émis via Baillan.';
  return PaymentReminderMessage(subject: subject, body: body);
}

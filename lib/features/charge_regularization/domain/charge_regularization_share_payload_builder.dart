import '../../../core/utils/french_date.dart';
import 'charge_regularization_balance.dart';

/// Résultat de la construction du payload de partage de l'avis de
/// régularisation des charges (FEAT-029 V1.2).
///
/// Même forme que `receipts/data/share_payload_builder.dart` — sujet, corps
/// pré-rempli, nom de fichier — réutilisée telle quelle pour le partage Web
/// Share API / fallback mailto:.
class ChargeRegularizationSharePayload {
  const ChargeRegularizationSharePayload({
    required this.subject,
    required this.body,
    required this.filename,
  });

  /// Sujet de l'email
  /// (ex: `"Régularisation des charges — 01/01/2025 au 31/12/2025"`).
  final String subject;

  /// Corps du message pré-rempli.
  final String body;

  /// Nom du fichier PDF pour le partage natif
  /// (ex: `"regularisation_charges_2025.pdf"`).
  final String filename;
}

/// Construit le [ChargeRegularizationSharePayload] pour le partage de l'avis
/// de régularisation. Pure — ne dépend d'aucun état externe, testable.
abstract final class ChargeRegularizationSharePayloadBuilder {
  static ChargeRegularizationSharePayload build({
    required ChargeRegularizationBalance balance,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) {
    final periodStartLabel = FrenchDate.format(balance.periodStart);
    final periodEndLabel = FrenchDate.format(balance.periodEnd);

    final subject =
        'Régularisation des charges — $periodStartLabel au $periodEndLabel';

    final body =
        'Bonjour $tenantFirstName,\n\n'
        'Veuillez trouver ci-joint l\'avis de régularisation annuelle des\n'
        'charges pour la période du $periodStartLabel au $periodEndLabel\n'
        'concernant le logement situé $propertyAddress.\n\n'
        'Ce décompte fait apparaître un solde ${balance.labelFr}.\n\n'
        'Cordialement,\n'
        '$landlordFullName\n\n'
        '---\n'
        'Émis par Baillan.';

    final filename = 'regularisation_charges_${balance.periodEnd.year}.pdf';

    return ChargeRegularizationSharePayload(
      subject: subject,
      body: body,
      filename: filename,
    );
  }
}

import '../../../core/utils/french_date.dart';
import '../domain/receipt.dart';

/// Résultat de la construction du payload de partage d'une quittance.
///
/// Contient les données nécessaires pour construire un mailto: ou une
/// notification à l'utilisateur lors du partage natif.
class SharePayload {
  const SharePayload({
    required this.subject,
    required this.body,
    required this.filename,
  });

  /// Sujet de l'email (ex: `"Quittance de loyer — mars 2026"`).
  final String subject;

  /// Corps du message pré-rempli.
  final String body;

  /// Nom du fichier PDF pour le partage natif (ex: `"quittance_mars_2026.pdf"`).
  final String filename;
}

/// Construit le [SharePayload] pour le partage d'une quittance.
///
/// Pure — ne dépend d'aucun état externe, facilement testable.
abstract final class SharePayloadBuilder {
  /// Construit un [SharePayload] à partir des métadonnées de la quittance.
  ///
  /// [receipt] : quittance source (période, montants).
  /// [tenantFirstName] : prénom du locataire.
  /// [propertyAddress] : adresse du logement.
  /// [landlordFullName] : nom complet du bailleur.
  static SharePayload build({
    required Receipt receipt,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) {
    final monthYear = FrenchDate.frenchMonthYear(receipt.periodStart);
    final subject = 'Quittance de loyer — $monthYear';

    final periodStartLabel = FrenchDate.format(receipt.periodStart);
    final periodEndLabel = FrenchDate.format(receipt.periodEnd);

    final body =
        'Bonjour $tenantFirstName,\n\n'
        'Veuillez trouver ci-joint votre quittance de loyer pour la période\n'
        'du $periodStartLabel au $periodEndLabel\n'
        'concernant le logement situé $propertyAddress.\n\n'
        'Cordialement,\n'
        '$landlordFullName\n\n'
        '---\n'
        'Émis par Baillan.';

    final filename = 'quittance_${_slugify(monthYear)}.pdf';

    return SharePayload(subject: subject, body: body, filename: filename);
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  /// Transforme un libellé en slug de nom de fichier sans espaces ni accents.
  ///
  /// Exemple : `"mars 2026"` → `"mars_2026"`,
  ///           `"août 2026"` → `"aout_2026"`.
  static String _slugify(String input) {
    const accentMap = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'œ': 'oe',
      'æ': 'ae',
    };

    var result = input.toLowerCase();
    accentMap.forEach((accented, plain) {
      result = result.replaceAll(accented, plain);
    });
    // Remplacer les espaces par des underscores et supprimer les caractères
    // non alphanumériques restants (hors underscore).
    result = result.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return result;
  }
}

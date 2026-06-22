/// Formatage de dates au format français `dd/MM/yyyy`.
///
/// Source unique partagée entre tous les widgets (FEAT-003 → FEAT-006 et
/// suivants). Évite la prolifération de petits `_formatDate` privés par
/// widget (8 copies recensées avant ce refactor).
///
/// Le format est volontairement minimal (pas d'heures) — pour l'affichage
/// d'un `timestamptz` complet, utiliser plutôt [package:intl/intl.dart].
class FrenchDate {
  const FrenchDate._();

  static const List<String> _monthNames = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// Formate une [date] au format français `dd/MM/yyyy`.
  ///
  /// Applique [DateTime.toLocal] pour gérer correctement les timestamps UTC
  /// (`created_at`, `updated_at` reviennent en UTC depuis Postgres).
  /// Pour un `DateTime` déjà local, l'appel est idempotent.
  static String format(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  /// Formate une string ISO `YYYY-MM-DD` au format `dd/MM/yyyy`.
  ///
  /// Retourne [isoDate] inchangée si le format est inattendu, ou une chaîne
  /// vide si l'entrée est vide (comportement défensif — utilisé pour des
  /// affichages de listes où une date manquante ne doit pas crasher).
  static String formatIsoString(String isoDate) {
    if (isoDate.isEmpty) return '';
    final parts = isoDate.split('-');
    if (parts.length < 3) return isoDate;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  /// Retourne le libellé "mois année" en français (ex: `"mars 2026"`).
  ///
  /// Utilisé pour les sujets d'email et noms de fichier des quittances.
  static String frenchMonthYear(DateTime date) {
    final d = date.toLocal();
    return '${_monthNames[d.month - 1]} ${d.year}';
  }
}

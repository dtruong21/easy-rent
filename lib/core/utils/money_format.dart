import 'package:intl/intl.dart';

/// Helpers de conversion euros ↔ centimes et formatage FR.
///
/// Règle fondamentale : les montants sont stockés et manipulés en **centimes**
/// (entiers) côté Dart et Postgres. La conversion en euros n'a lieu qu'à
/// l'affichage (UI) et à la saisie (formulaire). Jamais de `double` dans un
/// payload INSERT/UPDATE.
class MoneyFormat {
  const MoneyFormat._();

  /// Convertit une saisie euros (String) en centimes (int).
  ///
  /// Accepte la virgule (',') ou le point ('.') comme séparateur décimal.
  /// Supprime les espaces (insécables inclus).
  ///
  /// Retourne `null` si la valeur est vide, non numérique ou négative.
  /// Utilise `.round()` pour éviter les erreurs de virgule flottante
  /// (ex. : `84.99 * 100 = 8498.999...` → `.round()` → `8499`).
  static int? eurosToCents(String input) {
    final cleaned = input
        .trim()
        .replaceAll(' ', '') // espace insécable
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < 0) return null;
    if (!parsed.isFinite) return null;
    final cents = (parsed * 100).round();
    // Reject values that overflow Postgres integer (max 2,147,483,647).
    if (cents > 2147483647) return null;
    return cents;
  }

  /// Convertit des centimes (int) en euros (double).
  ///
  /// Utilisé pour pré-remplir les champs du formulaire.
  static double centsToEuros(int cents) => cents / 100;

  /// Formate des centimes en chaîne FR avec symbole € : "1 234,56 €".
  ///
  /// Utilise la locale `fr_FR` de `intl` — espace insécable comme séparateur
  /// de milliers, virgule comme séparateur décimal, symbole € en suffixe.
  static String formatEurosFromCents(int cents) {
    final euros = cents / 100;
    final formatter = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 2,
    );
    return formatter.format(euros);
  }

  /// Formate des centimes en chaîne FR sans symbole : "1234,56".
  ///
  /// Utilisé pour pré-remplir les champs texte du formulaire en mode édition.
  static String centsToInput(int cents) {
    final euros = cents / 100;
    return euros.toStringAsFixed(2).replaceAll('.', ',');
  }
}

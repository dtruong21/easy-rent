import 'package:intl/intl.dart';

/// Formatage de taille en octets vers une chaîne lisible en français.
///
/// Exemples :
/// - `0` → "0 o"
/// - `512` → "512 o"
/// - `1024` → "1,0 Ko"
/// - `870400` → "850,0 Ko"
/// - `2516582` → "2,4 Mo"
class ByteFormat {
  const ByteFormat._();

  static final _frDecimal = NumberFormat('#,##0.#', 'fr_FR');

  /// Formate [bytes] en chaîne FR avec unité (o / Ko / Mo).
  static String format(int bytes) {
    if (bytes < 1024) {
      return '$bytes o';
    }
    if (bytes < 1024 * 1024) {
      final ko = bytes / 1024;
      return '${_frDecimal.format(ko)} Ko';
    }
    final mo = bytes / (1024 * 1024);
    return '${_frDecimal.format(mo)} Mo';
  }
}

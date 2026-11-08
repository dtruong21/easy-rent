/// Police EB Garamond embarquée dans les PDF générés côté client (quittances
/// `receipts/data/receipt_pdf_renderer.dart`, avis de régularisation des
/// charges `charge_regularization/domain/charge_regularization_pdf_renderer.dart`).
///
/// Sans thème/police explicite, `pw.Document()` retombe sur Helvetica
/// base-14 (StandardFonts) : glyphe € absent (rendu en carré) et le
/// contournement historique consistait à retirer tous les accents français
/// des libellés — inacceptable sur un document à valeur légale (quittance,
/// loi du 6 juillet 1989). EB Garamond est déjà bundlée en asset (identité
/// Baillan, cf. `AppTheme._displayFontFamily`) et couvre U+20AC (€) et tout
/// le Latin-1 Supplement (accents français) — vérifié via `fc-scan`.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Charge et met en cache les 4 styles EB Garamond livrés en asset, puis
/// expose un [pw.ThemeData] prêt à passer à `pw.Document(theme: ...)`.
///
/// EB Garamond n'a pas de graisse Bold : `Medium` (500) en tient lieu pour
/// `bold` (titres, libellés, montant total) — c'est le choix retenu ici,
/// faute d'une variante Bold livrée avec la police. Pour `italic`/
/// `boldItalic`, `Italic` et `SemiBoldItalic` sont utilisées telles
/// quelles ; aucun des deux renderers actuels ne s'appuie sur du texte
/// italique, ces entrées ne servent qu'à compléter le thème.
///
/// Le chargement (lecture asset + parsing TTF par `pw.Font.ttf`) n'a lieu
/// qu'une seule fois par process : les appels suivants réutilisent le même
/// [Future] mis en cache. dart_pdf sous-ensemble de toute façon le glyphset
/// réellement utilisé à l'écriture du PDF (`TtfWriter.withChars`) — recharger
/// la police à chaque rendu n'aurait aucun bénéfice sur la taille du fichier
/// final, seulement un coût CPU inutile.
class PdfBrandFonts {
  const PdfBrandFonts._();

  static Future<pw.ThemeData>? _themeFuture;

  /// Thème EB Garamond (base/bold/italic/boldItalic), mis en cache après le
  /// premier appel.
  static Future<pw.ThemeData> theme() => _themeFuture ??= _load();

  static Future<pw.ThemeData> _load() async {
    final regular = await _loadFont('assets/fonts/EBGaramond-Regular.ttf');
    final medium = await _loadFont('assets/fonts/EBGaramond-Medium.ttf');
    final italic = await _loadFont('assets/fonts/EBGaramond-Italic.ttf');
    final semiBoldItalic = await _loadFont(
      'assets/fonts/EBGaramond-SemiBoldItalic.ttf',
    );
    return pw.ThemeData.withFont(
      base: regular,
      bold: medium,
      italic: italic,
      boldItalic: semiBoldItalic,
    );
  }

  static Future<pw.Font> _loadFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }
}

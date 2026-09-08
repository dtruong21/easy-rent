import 'package:flutter/material.dart';

import 'app_palette.g.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_radii.dart';
import '../ui/theme/app_spacing.dart';
import '../ui/theme/property_color.dart';

/// Thème Baillan. — papier + encre + olive (FEAT-020 rebrand).
///
/// Différences vs ancienne identité EasyRent (Material 3 seed indigo) :
///   - Fond papier chaud (#F7F4ED) au lieu de blanc neutre — feel "acte signé".
///   - Encre noire chaude (#1B1A17) au lieu de noir pur — moins clinique.
///   - Accent olive sourd (#3F4A2A) au lieu d'indigo — aucun concurrent
///     SaaS de gestion locative ne l'utilise, donc différenciant.
///   - Typo serif EB Garamond (bundlée en asset) pour le display (la marque,
///     les montants, les titres de quittance) — voix d'un acte signé.
///     Sans-serif système pour l'opérationnel (formulaires, tables,
///     navigation). Cf. plan de rebrand pour le détail.
///   - Oxblood (#9A3B2F) sur les états critiques uniquement (quittance
///     annulée, paiement en retard).
class AppTheme {
  const AppTheme._();

  // --- Palette Baillan. -----------------------------------------------------
  static const Color paper = AppPalette.paper;
  static const Color paperDeep = AppPalette.paperDeep;
  static const Color cream = AppPalette.cream;
  static const Color ink = AppPalette.ink;
  static const Color inkSurface = AppPalette.inkSurface;
  static const Color inkMuted = AppPalette.inkMuted;
  static const Color rule = AppPalette.rule;
  static const Color olive = AppPalette.olive;
  static const Color oliveMid = AppPalette.oliveMid;
  static const Color oliveSoft = AppPalette.oliveSoft;
  static const Color oxblood = AppPalette.oxblood;

  // --- Extensions Baillan (brand polish, 30 juin 2026) ----------------------
  //
  // Ces 8 jetons étendent la palette papier+encre+olive pour couvrir les
  // intentions sémantiques manquantes (états métier, interaction, comptabilité,
  // archive). Chacun a été choisi pour s'harmoniser avec l'encre chaude et
  // l'olive sourd — aucun vert fluo, aucun orange Slack.
  //
  // Pour le mapping vers les usages métier (Acquitté / Échu / Consigné /
  // Archivé), voir les alias sémantiques plus bas, et la table d'usage dans
  // docs/state/DESIGN_TOKENS.md.

  /// Vert wagon de sceau notarial — état "Acquitté" (quittance émise et payée).
  /// Distinct chromatiquement du primary olive (plus froid, plus profond) pour
  /// éviter la confusion action/état. Contraste 7.92:1 sur paper (AAA).
  static const Color sealGreen = AppPalette.sealGreen;

  /// Ocre tampon administratif — état "Échu imminent" (paiement dû <7j) ou
  /// brouillon non signé. Évoque l'encre brunie d'un timbre fiscal. Contraste
  /// 5.92:1 sur paper (AA).
  static const Color ochre = AppPalette.ochre;

  /// Encre d'encrier — état "Consigné" / mention légale (loi 1989, RGPD).
  /// Seule entorse au "pas de bleu" : bleu d'encrier presque noir, pas un bleu
  /// SaaS. Contraste 10.86:1 sur paper (AAA).
  static const Color indigoInk = AppPalette.indigoInk;

  /// Papier vergé saturé — surface "Archivé" / zone documents conservés.
  /// Texture distincte de paperDeep sans introduire une nouvelle teinte.
  /// Non utilisable pour texte (le texte ink reste à >13:1).
  static const Color kraft = AppPalette.kraft;

  /// Pierre — état "Disabled" / placeholder de champ vide. Délibérément sous
  /// le seuil WCAG (2.28:1 sur paper) — c'est exactement le bon ratio pour
  /// un disabled. Séparé d'inkMuted, qui reste un texte secondaire AA lisible.
  static const Color stone = AppPalette.stone;

  /// Olive profond — hover / pressed du primary olive. À utiliser à la place
  /// des opacity overlays Material 3 (qui produisent un olive grisé pâteux).
  /// Contraste 10.07:1 sur paper.
  static const Color oliveDeep = AppPalette.oliveDeep;

  /// Bordure renforcée — card sélectionnée / focus ring outline. rule
  /// (#E8E2D3, 1.18:1) est invisible sur paper ; ruleStrong (~3:1) distingue
  /// une card focus sans recourir à l'olive (réservé au primary).
  static const Color ruleStrong = AppPalette.ruleStrong;

  /// Brun encre — montants débiteurs en comptabilité (charges, sorties).
  /// Sépare sémantiquement "charge mensuelle" (neutre comptable) de "erreur
  /// système" (oxblood). Évite de dramatiser une opération normale. Contraste
  /// >8.5:1 sur paper.
  static const Color amountNegative = AppPalette.amountNegative;

  // --- Alias sémantiques métier (vocabulaire Baillan) -----------------------
  //
  // Pointent vers les jetons techniques ci-dessus, mais nommés depuis le
  // vocabulaire du bailliage. Un dev qui code "paiement confirmé" doit
  // écrire AppTheme.acquitte — pas sealGreen, pas Colors.green. Ces alias
  // sont la VOIX éditoriale du design system ("Acquitté", "Échu",
  // "Bailliage", "Tenir registre") portée jusqu'au code.

  /// État "Acquitté" — quittance émise, payée, signée. Alias de [sealGreen].
  static const Color acquitte = sealGreen;

  /// État "Échu" — échéance imminente (<7j) ou dépassée non encore régularisée.
  /// Alias de [ochre]. Distinct de [oxblood] qui reste pour "annulé / retard >30j".
  static const Color echu = ochre;

  /// État "Consigné" — mention légale, document archivé neutre, notification
  /// système non urgente. Alias de [indigoInk].
  static const Color consigne = indigoInk;

  /// Surface "Archivé" — bloc historique, pièces conservées, anciennes
  /// quittances. Alias de [kraft].
  static const Color archive = kraft;

  // --- Typographie ----------------------------------------------------------
  /// Sérif éditorial pour la marque, les montants, les titres de quittance.
  /// EB Garamond (licence OFL) est bundlée en asset — Flutter Web/CanvasKit
  /// ne résout pas les familles système CSS (Cochin, Palatino…), le rendu
  /// retomberait sur Roboto. Le fallback ne sert qu'en cas d'asset manquant.
  static const String _displayFontFamily = 'EB Garamond';
  static const List<String> _displayFontFamilyFallback = ['Georgia', 'serif'];

  // Sans-serif natif. Sur Flutter Web, "system-ui" est interprété par le
  // navigateur — SF Pro sur macOS/iOS, Segoe UI sur Windows, Roboto sur
  // Android. On laisse la valeur par défaut (Flutter utilise déjà ça quand
  // fontFamily n'est pas spécifié) — pas de surcharge inutile.

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: olive,
        onPrimary: paper,
        primaryContainer: oliveSoft,
        onPrimaryContainer: olive,
        secondary: inkMuted,
        onSecondary: paper,
        secondaryContainer: paperDeep,
        onSecondaryContainer: ink,
        tertiary: oliveMid,
        onTertiary: paper,
        tertiaryContainer: oliveSoft,
        onTertiaryContainer: ink,
        error: oxblood,
        onError: paper,
        errorContainer: Color(0xFFF3D9D4),
        onErrorContainer: oxblood,
        surface: paper,
        onSurface: ink,
        surfaceContainerLowest: cream,
        surfaceContainerLow: paper,
        surfaceContainer: paperDeep,
        surfaceContainerHigh: cream,
        surfaceContainerHighest: cream,
        onSurfaceVariant: inkMuted,
        outline: rule,
        outlineVariant: rule,
        inverseSurface: ink,
        onInverseSurface: paper,
        inversePrimary: oliveSoft,
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        surfaceTint: Color(0x00000000),
      );
    }
    // Dark mode : encre comme ground, papier comme texte.
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: oliveSoft,
      onPrimary: ink,
      primaryContainer: olive,
      onPrimaryContainer: paper,
      secondary: oliveSoft,
      onSecondary: ink,
      secondaryContainer: inkSurface,
      onSecondaryContainer: paper,
      tertiary: oliveMid,
      onTertiary: paper,
      tertiaryContainer: olive,
      onTertiaryContainer: paper,
      error: Color(0xFFD08176),
      onError: ink,
      errorContainer: Color(0xFF5A1F18),
      onErrorContainer: Color(0xFFF3D9D4),
      surface: ink,
      onSurface: paper,
      surfaceContainerLowest: Color(0xFF161512),
      surfaceContainerLow: ink,
      surfaceContainer: inkSurface,
      surfaceContainerHigh: inkSurface,
      surfaceContainerHighest: Color(0xFF353229),
      onSurfaceVariant: oliveSoft,
      outline: Color(0xFF4A463E),
      outlineVariant: Color(0xFF3A3730),
      inverseSurface: paper,
      onInverseSurface: ink,
      inversePrimary: olive,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      surfaceTint: Color(0x00000000),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final colorScheme = _scheme(brightness);

    // TextTheme : on applique le sérif EB Garamond sur les
    // display/headline (la voix éditoriale Baillan), et on laisse le système
    // sur body/label (lisibilité opérationnelle).
    //
    // Les montants en € seront stylés inline avec `tabularFigures` via
    // `font-variant-numeric: tabular-nums` quand nécessaire — on ne le force
    // pas globalement pour ne pas alourdir le rendu sur du texte courant.
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final baseText = base.textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
      decorationColor: colorScheme.onSurface,
    );

    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
      ),
      displayMedium: baseText.displayMedium?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.3,
      ),
      displaySmall: baseText.displaySmall?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontWeight: FontWeight.w400,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontWeight: FontWeight.w400,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontWeight: FontWeight.w400,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontFamily: _displayFontFamily,
        fontFamilyFallback: _displayFontFamilyFallback,
        fontWeight: FontWeight.w400,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      primaryTextTheme: textTheme,

      // AppBar : papier (light) ou encre (dark), pas de surface tint M3 qui
      // brouille la sobriété "feuille de papier".
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontFamily: _displayFontFamily,
          fontFamilyFallback: _displayFontFamilyFallback,
          fontStyle: FontStyle.italic,
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // Card : crème (light) / encre surface (dark), bordure rule subtile.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        subtitleTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),

      // FilledButton : olive sur papier (le geste fort).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // OutlinedButton : le geste secondaire — même langage que FilledButton
      // (rayon 4, même gabarit), contour discret, texte olive. Sans ce thème,
      // chaque écran redéfinissait son propre `styleFrom` → boutons secondaires
      // incohérents d'un écran à l'autre.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // TextButton : le geste tertiaire — texte olive, gabarit compact, même
      // rayon que les autres boutons.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),

      // Navigation (shell adaptatif FEAT-026) : rail + barre à la marque
      // papier/encre/olive — pas de surfaceTint M3, indicateur olive sourd
      // (primaryContainer), sélection en encre, non-sélection en encre atténuée.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),

      // Extensions de thème (statut pills, spacing, radii, couleurs d'identité
      // des biens — FEAT-057).
      extensions: [
        brightness == Brightness.light ? AppColors.light : AppColors.dark,
        const AppSpacing(),
        const AppRadii(),
        brightness == Brightness.light
            ? PropertyColorPalette.light
            : PropertyColorPalette.dark,
      ],
    );
  }
}

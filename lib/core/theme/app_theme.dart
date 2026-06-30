import 'package:flutter/material.dart';

import '../ui/theme/app_colors.dart';
import '../ui/theme/app_radii.dart';
import '../ui/theme/app_spacing.dart';

/// Thème Baillan. — papier + encre + olive (FEAT-020 rebrand).
///
/// Différences vs ancienne identité EasyRent (Material 3 seed indigo) :
///   - Fond papier chaud (#F7F4ED) au lieu de blanc neutre — feel "acte signé".
///   - Encre noire chaude (#1B1A17) au lieu de noir pur — moins clinique.
///   - Accent olive sourd (#3F4A2A) au lieu d'indigo — aucun concurrent
///     SaaS de gestion locative ne l'utilise, donc différenciant.
///   - Typo serif Cochin/Palatino pour le display (la marque, les montants,
///     les titres de quittance) — voix d'un acte signé. Sans-serif système
///     pour l'opérationnel (formulaires, tables, navigation). Cf. plan de
///     rebrand pour le détail.
///   - Oxblood (#9A3B2F) sur les états critiques uniquement (quittance
///     annulée, paiement en retard).
class AppTheme {
  const AppTheme._();

  // --- Palette Baillan. -----------------------------------------------------
  static const Color paper = Color(0xFFF7F4ED);
  static const Color paperDeep = Color(0xFFEFE9DA);
  static const Color cream = Color(0xFFFCFAF5);
  static const Color ink = Color(0xFF1B1A17);
  static const Color inkSurface = Color(0xFF2A2823);
  static const Color inkMuted = Color(0xFF6B665D);
  static const Color rule = Color(0xFFE8E2D3);
  static const Color olive = Color(0xFF3F4A2A);
  static const Color oliveMid = Color(0xFF5E6A45);
  static const Color oliveSoft = Color(0xFFB5B89D);
  static const Color oxblood = Color(0xFF9A3B2F);

  // --- Typographie ----------------------------------------------------------
  /// Sérif éditorial pour la marque, les montants, les titres de quittance.
  /// Cochin est natif sur macOS/iOS, Palatino l'est sur Windows, et le
  /// stack tombe en fallback Georgia/serif si rien d'autre n'est dispo.
  static const String _displayFontFamily = 'Cochin';
  static const List<String> _displayFontFamilyFallback = [
    'Palatino Linotype',
    'Book Antiqua',
    'Palatino',
    'Georgia',
    'serif',
  ];

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

    // TextTheme : on applique le stack serif Cochin/Palatino sur les
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

      // Extensions de thème (statut pills, spacing, radii).
      extensions: [
        brightness == Brightness.light ? AppColors.light : AppColors.dark,
        const AppSpacing(),
        const AppRadii(),
      ],
    );
  }
}

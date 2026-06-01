import 'package:flutter/material.dart';

/// Thème EasyRent — Material 3 avec seed teal.
///
/// `ColorScheme.fromSeed` ne suffit pas seul : sans sous-thèmes explicites,
/// les composants (AppBar, Card, Divider, ListTile…) héritent de défauts
/// Material 3 qui produisent des contrastes faibles, voire invisibles en
/// dark mode (texte sur fond surface trop proche). On force donc les sous-
/// thèmes pour garantir la lisibilité quel que soit le brightness système.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF0F766E);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,

      // AppBar : on force foreground/background pour éviter le rendu M3 par
      // défaut où le titre peut devenir invisible (surfaceTint dynamique mal
      // contrasté sur Safari dark mode notamment).
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // Card : surface légèrement surélevée pour démarquer du scaffold.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        margin: EdgeInsets.zero,
      ),

      // Divider : on garde `outlineVariant` (défaut M3) mais on force
      // thickness/space pour une mesure prévisible quel que soit le contexte.
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ListTile : icônes + texte alignés sur le scheme courant.
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        subtitleTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),

      // SnackBar : inversé par rapport au scaffold pour bonne visibilité.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),

      // Dialog : fond contrasté pour éviter le rendu "transparent" en dark.
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),

      // BottomSheet : idem.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),

      // Tooltip : contrasté pour rester lisible en dark.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),

      // Input : bordures explicites au lieu des défauts M3 souvent invisibles.
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

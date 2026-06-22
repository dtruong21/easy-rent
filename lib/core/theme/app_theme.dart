import 'package:flutter/material.dart';

import '../ui/theme/app_colors.dart';
import '../ui/theme/app_radii.dart';
import '../ui/theme/app_spacing.dart';

/// Thème EasyRent — Material 3 avec seed indigo.
///
/// `ColorScheme.fromSeed` ne suffit pas seul : sans sous-thèmes explicites,
/// les composants (AppBar, Card, Divider, ListTile…) héritent de défauts
/// Material 3 qui produisent des contrastes faibles, voire invisibles en
/// dark mode (texte sur fond surface trop proche). On force donc les sous-
/// thèmes pour garantir la lisibilité quel que soit le brightness système.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(
    0xFF4F46E5,
  ); // indigo-600 (était #0F766E teal-700)

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    // M3 génère un textTheme avec color=null sur chaque TextStyle ; la couleur
    // est injectée par les widgets Material via DefaultTextStyle. Mais certains
    // widgets ne s'appuient pas dessus — typiquement RichText / TextSpan, qui
    // tombent alors sur le fallback `Colors.black` → invisible en dark mode.
    // On force la couleur via .apply() pour que tout texte soit lisible.
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme;
    final textTheme = baseTextTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
      decorationColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      primaryTextTheme: textTheme,

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

      // Extensions de thème EasyRent (FEAT-012 Phase 0).
      extensions: [
        brightness == Brightness.light ? AppColors.light : AppColors.dark,
        const AppSpacing(),
        const AppRadii(),
      ],
    );
  }
}

# Thème Material 3 — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/theme/app_theme.dart`. **Dernière sync** : 2026-06-01 (commits dd1673e, 870c335, fixes dark mode visibility)

## Vue d'ensemble

EasyRent utilise Material Design 3 avec seed color **teal** (`#0F766E`). La palette est générée dynamiquement via `ColorScheme.fromSeed()`.

**Problème historique** (fix commits dd1673e, 870c335) :
- M3 par défaut : textTheme sans couleur explicite → confiée à `DefaultTextStyle` de chaque widget
- RichText/TextSpan ne s'appuient PAS sur `DefaultTextStyle` → fallback `Colors.black` → **invisible en dark mode**
- Certains sous-thèmes (AppBar, ListTile, Dialog) héritaient de défauts M3 : contrastes faibles ou surfaceTint mal appliqué

**Solution** : Appliquer `textTheme.apply(bodyColor, displayColor)` + rédef complète des sous-thèmes pour garantir lisibilité.

## Structure

### Fichier principal

**Path** : `lib/core/theme/app_theme.dart`

```dart
class AppTheme {
  static const Color _seed = Color(0xFF0F766E);  // Teal
  
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
}
```

**Invocation** : `lib/main.dart`

```dart
MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  // … routerConfig, etc.
)
```

## Sous-thèmes explicites

| Composant | Fix appliqué |
|---|---|
| **TextTheme** | `.apply(bodyColor: onSurface, displayColor: onSurface, decorationColor: onSurface)` — force couleur sur tous les TextStyles |
| **AppBar** | backgroundColor=surface, foregroundColor=onSurface, surfaceTintColor=transparent, titleTextStyle=explicit |
| **Card** | color=surfaceContainerHigh, elevation=1, surfaceTintColor=transparent |
| **ListTile** | iconColor=onSurfaceVariant, textColor=onSurface, subtitleTextStyle=explicit |
| **Dialog** | backgroundColor=surfaceContainerHigh, surfaceTintColor=transparent |
| **SnackBar** | backgroundColor=inverseSurface, contentTextStyle=explicit onInverseSurface |
| **BottomSheet** | backgroundColor=surfaceContainerHigh, surfaceTintColor=transparent |
| **Tooltip** | decoration=inverseSurface + textStyle=explicit |
| **InputDecoration** | border=OutlineInputBorder explicit, focusedBorder=primary |
| **Divider** | color=outlineVariant, thickness=1, space=1 |

## Pallette de couleurs

### Modes clair et sombre

Flutter M3 génère automatiquement via `ColorScheme.fromSeed(brightness: …)` :
- Primaire, secondary, tertiary
- Surface, surfaceContainer, surfaceContainerHigh, surfaceContainerHighest
- onSurface, onSurfaceVariant
- Outline, outlineVariant
- Error, errorContainer
- Inverse, inverseSurface, inversePrimary

Aucune couleur custom codée en dur — tout dérivé du seed teal.

## Testé

- ✅ **Light mode** : Lisibilité vérifiée sur tous les composants
- ✅ **Dark mode** : RichText/TextSpan visible (fix #16 — Google Fonts CSP + theme coordination)
- ✅ **High contrast** : Contrastes WCAG AA+ sur textes + icônes

## Changements futurs

- Potentiel : Permettre user-switchable theme (light/dark/system) via paramètre `themeMode`
  - Actuellement : `MaterialApp.router(…)` utilise défaut système
  - Prêt pour : Riverpod provider `themePreferenceProvider` + `themeMode` StateNotifier

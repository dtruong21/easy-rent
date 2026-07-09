# Thème — snapshot

> Maintenu par `state-keeper`. **Source** : [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart).
> **Palette hex → usage métier** : voir [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md) (source de vérité des couleurs, ne pas dupliquer ici).
> **Dernière sync** : 2026-07-08 (rebrand Baillan FEAT-020 + brand polish 30 juin + nav shell FEAT-026 + `themeMode` utilisateur).

## Vue d'ensemble

L'app utilise le thème **Baillan** — *papier + encre + olive* (FEAT-020). Ce n'est **plus** un thème Material 3 généré par seed : le `ColorScheme` clair et sombre est **écrit à la main** (`const ColorScheme(...)`), pour tenir la posture de marque « acte signé ».

> ⚠️ Historique : l'ancienne identité EasyRent était un M3 `ColorScheme.fromSeed(seed: teal #0F766E)`. Elle est **abandonnée**. Toute doc/agent qui mentionne « seed teal » ou `fromSeed()` est périmé.

Principes de la palette (détail dans [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md)) :
- Fond **papier** chaud `#F7F4ED` (`paper`) au lieu de blanc neutre.
- **Encre** noire chaude `#1B1A17` (`ink`) au lieu de noir pur.
- Accent **olive** sourd `#3F4A2A` (`olive`) au lieu d'indigo — différenciant SaaS.
- **Oxblood** `#9A3B2F` réservé aux états critiques (quittance annulée, retard >30j).

## Structure

**Path** : [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart)

```dart
class AppTheme {
  const AppTheme._();

  // Palette exposée en constantes statiques (paper, ink, olive, oxblood, …)
  static const Color paper = Color(0xFFF7F4ED);
  static const Color ink   = Color(0xFF1B1A17);
  static const Color olive = Color(0xFF3F4A2A);
  // … + 8 jetons d'extension + 4 alias sémantiques (acquitte/echu/consigne/archive)

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);
}
```

Les **jetons de couleur, alias sémantiques et jetons d'extension** vivent directement sur `AppTheme` (constantes) — c'est là qu'on lit/ajoute une couleur, pas dans un `ColorScheme.fromSeed`. Un dev qui code un état métier utilise l'**alias sémantique** (`AppTheme.acquitte`), jamais une couleur en dur.

**Invocation** : [`lib/main.dart`](../../lib/main.dart) (thème désormais **switchable par l'utilisateur**)

```dart
final themeMode = ref.watch(themeModeProvider); // Système / Clair / Sombre
MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: themeMode, // persisté en localStorage (Profil → Apparence)
  // … routerConfig, i18n, etc.
)
```

`themeModeProvider` ([`lib/core/theme/theme_mode_provider.dart`](../../lib/core/theme/theme_mode_provider.dart)) : `StateNotifier<ThemeMode>`, défaut `system`, préférence persistée via `ThemeModeStorage` (localStorage). **N'est pas** `autoDispose` (vit toute la session).

## ColorScheme (écrit à la main)

Deux `const ColorScheme` explicites dans `_scheme(Brightness)` — aucune dérivation automatique. Mapping des rôles M3 vers la palette Baillan :

| Rôle M3 | Light | Dark |
|---|---|---|
| `primary` | `olive` | `oliveSoft` |
| `onPrimary` | `paper` | `ink` |
| `primaryContainer` | `oliveSoft` | `olive` |
| `secondary` | `inkMuted` | `oliveSoft` |
| `tertiary` | `oliveMid` | `oliveMid` |
| `error` / `onError` | `oxblood` / `paper` | `#D08176` / `ink` |
| `surface` (scaffold) | `paper` | `ink` |
| `onSurface` (texte) | `ink` | `paper` |
| `surfaceContainerLowest` | `cream` | `#161512` |
| `surfaceContainer` | `paperDeep` | `inkSurface` |
| `surfaceContainerHigh` (cards/dialogs) | `cream` | `inkSurface` |
| `onSurfaceVariant` | `inkMuted` | `oliveSoft` |
| `outline` / `outlineVariant` | `rule` | `#4A463E` / `#3A3730` |
| `inverseSurface` / `onInverseSurface` | `ink` / `paper` | `paper` / `ink` |
| `surfaceTint` | **transparent** (`0x00000000`) | **transparent** |

**Dark mode = inversion papier/encre** : l'encre devient le ground, le papier devient le texte, l'olive s'éclaircit en `oliveSoft`. `surfaceTint` est neutralisé partout pour éviter le voile M3.

## Typographie

- **Display / headline / title** → sérif éditorial **EB Garamond** (licence OFL, **bundlé en asset** — CanvasKit ne résout pas les familles système CSS). `displayLarge`/`displayMedium` en *italique* `w400`, letter-spacing négatif. Fallback `['Georgia', 'serif']` uniquement si l'asset manque.
- **Body / label** → sans-serif **système** (pas de `fontFamily` forcée : SF Pro / Segoe UI / Roboto selon l'OS).
- `textTheme.apply(bodyColor / displayColor / decorationColor = onSurface)` : force la couleur sur tous les `TextStyle` (garantit la lisibilité RichText/TextSpan qui n'héritent pas de `DefaultTextStyle`, surtout en dark).
- Titre d'`AppBar` : EB Garamond italique 22px.
- Montants € : `tabularFigures` appliqué **inline** au besoin, pas globalement.

## Sous-thèmes explicites

Rayon de bordure standard = **4px** sur la plupart des composants.

| Composant | Réglage |
|---|---|
| **AppBar** | `background=surface`, `foreground=onSurface`, `surfaceTint=transparent`, `elevation=0` (`scrolledUnder=1`), titre EB Garamond italique 22 |
| **Card** | `color=surfaceContainerHigh`, `elevation=0`, `margin=zero`, radius 4, bordure `outlineVariant` |
| **Divider** | `color=outlineVariant`, `thickness=1`, `space=1` |
| **ListTile** | `iconColor=onSurfaceVariant`, `textColor=onSurface`, subtitle explicite 14 |
| **SnackBar** | `background=inverseSurface`, texte `onInverseSurface`, action `inversePrimary`, `behavior=floating` |
| **Dialog** | `background=surfaceContainerHigh`, `surfaceTint=transparent` |
| **BottomSheet** | `background=surfaceContainerHigh`, `surfaceTint=transparent` |
| **Tooltip** | `decoration=inverseSurface` radius 4, texte `onInverseSurface` |
| **FilledButton** | `background=primary`, `foreground=onPrimary`, radius 4, padding 22×14, `w600` |
| **InputDecoration** | `filled`, `fill=surfaceContainerHigh`, borders radius 4 (`enabled=outline`, `focused=primary width 2`) |
| **NavigationRail / NavigationBar** (shell FEAT-026) | `background=surface`, `indicator=primaryContainer` (olive sourd), sélection `onSurface` `w600`, non-sélection `onSurfaceVariant`, `surfaceTint=transparent` |

## Extensions de thème (`ThemeData.extensions`)

Injectées dans `_build()` selon la brightness :

| Extension | Path | Contenu |
|---|---|---|
| **AppColors** | [`lib/core/ui/theme/app_colors.dart`](../../lib/core/ui/theme/app_colors.dart) | Palette des **status pills** : 5 tones (success/warning/danger/info/neutral) × 4 couleurs (surface/onSurface/solid/onSolid), déclinée light/dark. Accès : `Theme.of(context).extension<AppColors>()!.statusFor(tone)`. |
| **AppSpacing** | [`lib/core/ui/theme/app_spacing.dart`](../../lib/core/ui/theme/app_spacing.dart) | Espacements : `xs 4 / sm 8 / md 12 / lg 16 / xl 24 / xxl 32`, `gridGap 16`, `cardPaddingCompact 12`, `cardPaddingStandard 16`. |
| **AppRadii** | [`lib/core/ui/theme/app_radii.dart`](../../lib/core/ui/theme/app_radii.dart) | Rayons : `sm 6 / md 10 / lg 14 / pill 999`. |

## Écarts connus / dette (à ne pas prendre pour la cible)

- ⚠️ **`AppColors` (status pills) est encore la palette Tailwind héritée d'EasyRent** (vert `#15803D`, ambre, rouge, sky, slate) — **pas** la palette olive/oxblood. Migration prévue (cf. TODO §6 de [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md)).
- Les 8 **jetons d'extension** (`sealGreen`, `ochre`, `indigoInk`, `kraft`, `stone`, `oliveDeep`, `ruleStrong`, `amountNegative`) et alias (`acquitte`/`echu`/`consigne`/`archive`) existent comme constantes mais **ne sont pas tous câblés** dans les sous-thèmes : `oliveDeep` n'est pas branché en hover/pressed du `FilledButton`, `ruleStrong` pas dans le focus ring des cards. À câbler côté widget/sous-thème.
- EB Garamond est bundlé en asset ; IBM Plex Sans (body non-système) reste un follow-up.

## Testé

- ✅ **Light** & **Dark** : lisibilité vérifiée, RichText/TextSpan visible (couleurs forcées via `textTheme.apply`).
- ✅ `surfaceTint` neutralisé → pas de voile M3 sur cards/appbar/dialogs.
- ✅ `themeMode` utilisateur (Système/Clair/Sombre) persisté et appliqué.

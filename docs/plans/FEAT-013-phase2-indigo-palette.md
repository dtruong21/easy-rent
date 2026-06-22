# Plan — FEAT-013 Phase 2 — Modern Indigo palette refresh

> Designé par architect le 2026-06-22. À démarrer après merge Phase 1 (back buttons + transitions).

## 1. Vue d'ensemble

Seed `#0F766E` (teal-700) → **`#4F46E5`** (indigo-600 Tailwind, palette Stripe/Linear/Mercury). User feedback : couleur actuelle trop sombre/triste.

**Cible** : 1 PR mergeable en ~3h. Changement minimal : un seul seed, Material 3 propage automatiquement.

**Branche** : `feature/feat-013-phase2-indigo-palette` post-merge Phase 1.

**Pas de migration SQL, pas de nouvelle dépendance.**

## 2. Changement seed

```dart
// lib/core/theme/app_theme.dart ligne 17
static const Color _seed = Color(0xFF4F46E5);  // indigo-600 (était #0F766E teal-700)
```

`ColorScheme.fromSeed(seedColor: indigo, brightness: ...)` dérive automatiquement :
- `primary` light → indigo-600 `#4F46E5`, dark → indigo-200 `#C7D2FE`
- `onPrimary` light → white, dark → indigo-900 `#312E81`
- `primaryContainer` / `onPrimaryContainer` / `secondary` / `tertiary` adaptés
- `surface` / `onSurface` quasi inchangés (neutral)

**Aucune occurrence de `colorScheme.primary` ne nécessite de modif** — les widgets héritent via le thème.

## 3. Audit couleurs hardcodées

`grep "Color(0xFF" lib/` retourne uniquement :
- `lib/core/ui/theme/app_colors.dart` (palette sémantique — pas à toucher)
- `lib/core/theme/app_theme.dart` ligne 17 (seed à changer)

**0 autre couleur hardcodée dans `lib/`**.

Références au teal hors `lib/` :
- `web/index.html` lignes 23, 40 (meta theme-color + body bg)
- `web/manifest.json` lignes 7, 8 (background_color + theme_color)
- `scripts/generate_pwa_icons.dart` lignes 7, 32, 45 (RGB + doc)

## 4. AppColors sémantique : INCHANGÉ

`AppColors` (success/warning/danger/info/neutral) reste strictement identique — c'est sémantique universel, indépendant du branding.

## 5. Composants à vérifier visuellement

| Composant | Risque |
|---|---|
| `kpi_card.dart` | Aucun — plus vibrant = mieux |
| `recent_activity_section.dart` | Aucun |
| `monthly_barchart.dart` (barre "encaissé" = `info.solid` bleu cyan) | **Conflit visuel** : info `#0284C7` vs primary indigo `#4F46E5` proches — voir §6 |
| `lease_status_badge.dart` (`active` → `primary`) | Aucun |
| `entity_card.dart` (border `primary` selected) | Plus marqué (positif) |
| Auth pages (icônes `primary`) | Plus chaleureux |
| Status pills | Aucun (palette sémantique inchangée) |

## 6. Conflit "info" vs "primary" → arbitrage

`MonthlyBarchart` barre "encaissé" = `info.solid` (`#0284C7`). Avec primary indigo `#4F46E5`, conflit visuel proche.

**Décision recommandée** : passage à **`AppColors.success.solid`** (vert `#15803D`) pour la barre encaissé.

Justification :
- Sémantique métier renforcée (vert = argent rentré = positif)
- Évite conflit indigo
- Aligné Stripe/Brex (vert = "income received")
- 1 ligne à changer (`monthly_barchart.dart`)
- Barre "dû" reste `neutral.surface` gris pâle

## 7. Dark mode

M3 dark avec seed indigo :
- `surface` ~`#13111B` (sombre neutre légèrement violacé)
- `primary` `#C7D2FE` (indigo-200 clair)
- `onPrimary` `#312E81` (indigo-900)

Fixes historiques `app_theme.dart` (textTheme.apply + sous-thèmes) restent valides — ils consomment `colorScheme.onSurface`/`onPrimary` calculés par M3.

**À vérifier QA** : KPI cards + barchart dark — lisibilité OK (WCAG AA garanti par M3 fromSeed).

## 8. Fichiers à modifier

1. `lib/core/theme/app_theme.dart` — ligne 17 (seed) + doc
2. `lib/features/dashboard/presentation/widgets/monthly_barchart.dart` — lignes barre encaissée (info → success)
3. `web/index.html` — lignes 23, 40
4. `web/manifest.json` — lignes 7, 8
5. `scripts/generate_pwa_icons.dart` — lignes 7, 32, 45 (RGB `79, 70, 229`)
6. `docs/state/THEME.md` — post-merge

**Optionnel mais recommandé** : régénérer les 4 PNG `web/icons/` via `dart run scripts/generate_pwa_icons.dart` (~30 sec).

## 9. Tests

- `flutter analyze` clean
- `dart format` clean
- `flutter test` (~1300 tests passent — aucun ne dépend de la couleur primary)
- QA manuel staging : login, signup, dashboard, properties, leases, receipts, dark mode toggle, PWA install
- `Colors.teal` dans 19 fichiers test/ : **conservé** (seed arbitraire de test, sans lien avec le branding)

## 10. Effort

| Tâche | Heures |
|---|---|
| Modif seed + barchart + web/* assets | 0.5 |
| Régénération PNG icons (script) | 0.25 |
| analyze + tests + fixes | 0.5 |
| QA visuelle complète (light + dark) | 1 |
| Screenshots avant/après pour PR | 0.5 |
| Review code + security | 0.5 |
| **Total** | **~3 h** |

## 11. Décisions verrouillées

| # | Décision |
|---|---|
| 1 | Seed = `#4F46E5` indigo-600 |
| 2 | AppColors sémantique INCHANGÉ |
| 3 | Pas de `colorScheme.copyWith()` (confiance dans fromSeed) |
| 4 | Barchart "encaissé" = `success.solid` vert (vs primary indigo) |
| 5 | PWA icons régénérées dans la même PR |
| 6 | `Colors.teal` dans tests conservé |
| 7 | Hors scope : typo, icons Lucide, logo refresh, glassmorphism |

## 12. Risques

1. **Contraste dark mode** indigo-200 / surface très sombre — WCAG AA garanti par M3, QA visuelle valide
2. **Conflit visuel barchart** — mitigé via §6 (success vert au lieu de info bleu)
3. **PWA icons placeholder** si script non relancé — étape 7 explicite dans le scope
4. Pas de logo produit dédié — aucun asset à updater

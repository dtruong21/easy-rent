# Conventions techniques EasyRent

## Flutter

- Structure : `lib/features/<feature>/{data,domain,presentation}`
- State : **Riverpod** (pas de `setState` pour app state)
- Navigation : **go_router** (shell adaptatif, voir « Navigation & UX » ci-dessous)
- Modèles : **freezed** + **json_serializable**
- Format : `dart format .` avant commit, `flutter analyze` zéro warning
- Logs : `package:logging`, jamais `print()`
- Locale : UI en français, code en anglais
- Widgets : < 200 lignes, sinon extract
- Secrets : `--dart-define`, jamais en dur

## Supabase

- Migrations versionnées : `supabase/migrations/<YYYYMMDDHHMMSS>_<desc>.sql`
- **RLS activée sur toutes les tables**
- Policy template :
  ```sql
  CREATE POLICY "landlord_owns_<table>"
  ON <table> FOR ALL
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());
  ```
- Tous les FK ont un index
- Toutes les tables ont `created_at timestamptz default now()` + `updated_at`
- Soft-delete (`deleted_at`) plutôt que DELETE pour les entités à rétention légale
- Storage : buckets privés, paths préfixés par `auth.uid()`
- Edge Functions : Deno + TypeScript, validation Zod, vérif JWT

## Navigation & UX (FEAT-026)

> Concept complet et faisant autorité : [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md).
> Résumé des règles d'or à respecter dans tout code de navigation :

1. **Destinations persistantes.** Navigation via un **shell adaptatif**
   (`StatefulShellRoute.indexedStack`) : `NavigationBar` en bas < 600 px,
   `NavigationRail` à gauche ≥ 600 px. 5 branches : Accueil, Biens, Locataires,
   Baux, Profil. Même structure web et mobile.
2. **Pas de hub obligatoire.** Le dashboard est l'onglet **Accueil**, pas un
   passage forcé. Ne jamais `go('/dashboard')` pour « revenir au menu ».
3. **`goBranch` pour changer d'onglet, `push` pour approfondir.** `go()` est
   réservé aux deep links et au drill-down KPI (reset de pile voulu).
4. **Formulaires & détails = sous-pages empilées** (`push`), jamais des
   destinations. Pattern de référence : le hub `/profile` (FEAT-025b) → tuiles
   qui `push()` vers `/profile/{details,password,support}`.
5. **Breakpoint 600 px** pour l'idiome mobile ↔ desktop. Respecter `SafeArea`
   (NavigationBar au-dessus du home indicator ; prépare FEAT-024).
6. **Racines de branche sans bouton retour** (`showBackButton: false`) ;
   sous-pages avec retour natif (`BackButton` qui `pop()` dans la branche,
   `fallbackRoute` = racine de la branche en filet deep-link).
7. **Hors shell** : landing, écrans d'auth, `/privacy`, `/terms`, et le
   **simulateur** (accessible aux anonymes, plein écran) — jamais dans la barre
   d'onglets.

## Git

- Branche : `feat/<slug>`, `fix/<slug>`, `chore/<slug>`
- Commits conventionnels : `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`
- PR vers `main` obligatoire, squash merge
- Branch protection : `main` ne reçoit pas de push direct

## Structure dossiers

```
EasyRent/
├── lib/                       # Code Flutter
├── test/                      # Tests Dart
├── integration_test/          # Tests E2E
├── web/                       # Assets PWA
├── supabase/
│   ├── migrations/
│   ├── functions/
│   └── tests/
├── docs/
│   ├── ROADMAP.md
│   ├── BACKLOG.md
│   ├── CONVENTIONS.md         # ce fichier
│   ├── LEGAL.md
│   ├── AGENTS.md
│   ├── backlog/               # user stories individuelles
│   ├── plans/                 # plans techniques
│   ├── reviews/               # rapports de review
│   ├── qa-reports/
│   ├── security-audits/
│   ├── bug-hunts/
│   ├── releases/
│   ├── scout-reports/
│   ├── auto-loop/
│   └── state/                 # snapshot vivant du projet (cache)
├── .github/workflows/
└── .claude/
    ├── agents/
    ├── commands/
    └── settings.json
```

## Tests

- Unit : `test/unit/...`
- Widget : `test/widget/...`
- Integration : `integration_test/`
- RLS : `supabase/tests/rls_<table>.sql`
- Toujours tester le chemin malheureux (inputs invalides, erreurs réseau, états vides)
- Locale française dans les tests (dates, devise)

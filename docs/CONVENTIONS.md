# Conventions techniques EasyRent

## Flutter

- Structure : `lib/features/<feature>/{data,domain,presentation}`
- State : **Riverpod** (pas de `setState` pour app state)
- Navigation : **go_router**
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

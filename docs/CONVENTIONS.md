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

## Firestore

> Pivot FEAT-019 (2026-06-30) : migration du backend vers Firestore. État détaillé et
> faisant autorité : [`docs/state/schema/`](state/schema/README.md).

- Champs en **camelCase**. Montants en **centimes** (`*Cents`, int). Dates =
  `timestamp`. IDs = UUID string, sauf `landlords` / `paid_plan_interest` dont
  le docId **est** l'UID Firebase Auth.
- **Règles obligatoires sur toutes les collections**, deny-by-default +
  allowlist. Helpers de `firestore.rules` : `isOwner`, `isActive`,
  `preservesImmutables`, `isFullyAuthed`, `isAnonymous`, `isSignedIn`.
- **`allow list: if isOwner(resource.data.landlordId)`** sur les collections
  multi-tenant → toute query **doit** porter `where('landlordId','==',uid)`.
  Les règles ne sont pas des filtres : sans le `where`, la query échoue.
- **Soft-delete** : `deletedAt` timestamp\|null, jamais de hard-delete client
  (`delete` interdit dans les rules). La suppression passe par le callable
  `softDeleteEntity`. `receipts` est exclu (rétention légale 5 ans).
- **Immutables** côté client : `landlordId`, `createdAt`, `deletedAt` —
  protégés par `preservesImmutables()`.
- Toute query filtrant `deletedAt` a son **index composite** déclaré dans
  `firestore.indexes.json` (28 à ce jour).
- **Cloud Functions** : Node 20 + TypeScript, dans `functions/src/`
  (`callable/`, `triggers/`, `scheduled/`, `http/`). Les écritures sensibles
  (`leases`, `payments`, `documents`, `expenses`) sont **exclusives aux CF** —
  le client n'écrit pas directement.
- **Storage** : buckets privés, signed URLs 5 min, paths préfixés par l'UID.

## Cloud Storage (CLI)

- **`gcloud storage`, jamais `gsutil`.** Google retire `gsutil` du bundle
  `gcloud` par défaut à partir de **mars 2027** ; il faudra alors l'installer
  séparément via PyPI et configurer son auth à part (le standalone ne partage
  pas les credentials `gcloud`).
- Équivalents usuels : `gsutil cp` → `gcloud storage cp`, `gsutil rsync` →
  `gcloud storage rsync`, `gsutil ls` → `gcloud storage ls`.
- S'applique aux scripts de backup/migration de buckets (le bucket Firebase
  Storage du projet `easy-rent-54cd4` est un bucket GCS).
- Le déploiement courant n'utilise **ni `gcloud` ni `gsutil`** : `firebase-tools`
  passe par l'API REST. Cette règle vaut pour tout script ajouté plus tard.

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

> Modèle complet (releases, hotfixes, back-merge) :
> [`docs/GITFLOW.md`](GITFLOW.md).

- Branche : `feat/<slug>`, `fix/<slug>`, `chore/<slug>`, `docs/<slug>` —
  toujours **depuis `develop`**
- Commits conventionnels : `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`
- **PR vers `develop`** (pas `main`), squash merge. `develop` déploie sur
  staging ; la promotion `develop` → `main` déploie en prod.
- Hotfix critique uniquement : branche depuis `main`, puis back-merge `develop`
- Branch protection : ni `main` ni `develop` ne reçoivent de push direct

## Structure dossiers

```
EasyRent/
├── lib/                       # Code Flutter (core/, features/, l10n/)
├── test/                      # Tests Dart (unit/, widget/, integration/, core/, l10n/)
├── web/                       # Assets PWA
├── android/ ios/              # Apps natives (FEAT-024)
├── assets/                    # Fonts, images
├── tool/                      # Scripts Dart (branding/, release/, seed/)
├── functions/                 # Cloud Functions Node 20 + TS
│   ├── src/                   # callable/ triggers/ scheduled/ http/ utils/
│   ├── rules-tests/           # Tests règles Firestore (émulateur)
│   └── scripts/
├── firestore.rules            # Règles (deny-by-default)
├── firestore.indexes.json     # 28 index composites
├── storage.rules
├── firebase.json
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
- Integration : `test/integration/...`
- Cloud Functions : `functions/src/__tests__/` (vitest) → `npm test` dans `functions/`
- Règles Firestore : `functions/rules-tests/firestore_rules.test.ts` →
  `npm run test:rules` (lance l'émulateur Firestore, projet `demo-easyrent`).
  **Toujours tester le cross-user** : un landlord ne doit jamais lire/écrire
  les documents d'un autre (cf. DoD dans `CLAUDE.md`).
- Toujours tester le chemin malheureux (inputs invalides, erreurs réseau, états vides)
- Locale française dans les tests (dates, devise)

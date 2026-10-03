# Handoff — reprise sur une autre machine

> Rédigé le 2026-07-06. Réf `develop` : voir dernier commit `docs(state)`.
> But : reprendre le développement / déploiement de Baillan sur un nouveau PC.

## 1. Récupérer le code
```bash
git clone git@github.com:dtruong21/easy-rent.git
cd easy-rent && git checkout develop
```
`develop` contient tout : MVP + **FEAT-036** (charges récupérables/non-récupérables) + **FEAT-041 V1** (suivi des dépenses, collection `expenses`) + **FEAT-042** (mode de charges provisions/forfait + éligibilité régularisation) + fixes CI/tests + `docs/state/*` à jour.

## 2. Prérequis à installer (NE sont PAS dans Git)
- **Flutter 3.41.2** — ⚠️ version **épinglée** dans `.github/workflows/ci.yml` ; matcher cette version en local pour éviter les divergences (assertion `ListTile`/`DecoratedBox` sur Flutter plus récent).
- **Node.js 22** — pour les Cloud Functions.
- **firebase-tools** : `npm i -g firebase-tools` (ou `npx -y firebase-tools@latest`).
- (optionnel) **gh** CLI pour les PRs.

## 3. Setup projet
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regénère *.freezed.dart / *.g.dart (gitignorés)
npm --prefix functions ci                                   # deps Cloud Functions
```

## 4. Authentification (par machine, hors Git)
```bash
firebase login   # compte ayant accès au projet Firebase unique : easy-rent-54cd4
gh auth login    # optionnel (PRs / CI)
```

## 5. Lancer / tester
```bash
flutter run -d chrome
flutter test
(cd functions && npm test)
```

## 6. Déploiement (⚠️ UN SEUL projet Firebase = easy-rent-54cd4)
- **Staging (frontend)** : AUTOMATIQUE au push/merge sur `develop` → site hosting `baillan-stage`, canal `live` (workflow `Deploy`).
- **Backend** (functions + rules + indexes) : **MANUEL** (le pipeline ne déploie que le hosting). Comme dev/prod partagent le projet, ceci touche aussi la prod :
  ```bash
  firebase deploy --only functions,firestore:rules,firestore:indexes --project easy-rent-54cd4
  ```
  ⏳ Les index composites Firestore se construisent en asynchrone (console → Firestore → Indexes : attendre « Enabled »).
- **PROD** : merger `develop` → `main` (déclenche `Deploy` sur le site `prod`, canal `live`) **+** deploy backend manuel. Décision explicite requise.
  - Prod : `https://baillan.com` · Staging : `https://stage.baillan.com` (deux **sites** du même projet, données communes).
- Détails : `docs/ENVIRONMENTS.md`, `docs/GITFLOW.md`.

## 7. En attente / prochaines étapes
- **FEAT-031 — Rappels automatiques de paiement** : conçu (`docs/plans/FEAT-031-rappels-paiement.md`), **en pause**. Prérequis : acheter un **domaine** + choisir un fournisseur email (reco **Mailjet** — gratuit à ce volume, hébergement FR/EU) + configurer **SPF/DKIM**, puis extension Trigger Email OU envoi via API dans une Cloud Function.
- **FEAT-041 V1.1** : rentabilité sur dépenses **réelles** (hook présentation) + instantané figé de régularisation (reliquat FEAT-033).

## 8. État des features (voir `docs/state/FEATURES.md` pour le détail)
✅ Livrées + déployées staging : FEAT-036, FEAT-041 V1, FEAT-042. ⏸️ FEAT-031 (email). 📋 FEAT-041 V1.1.

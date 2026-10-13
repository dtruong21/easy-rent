# EasyRent

> Outil de gestion locative au format PWA, conçu pour les propriétaires français.

## ✨ Fonctionnalités (MVP)

- 🔐 Authentification propriétaire (email/mot de passe, Google, Apple, mode anonyme)
- 🏠 Gestion des biens immobiliers
- 👥 Gestion des locataires
- 📋 Gestion des baux (loyer, charges, durée, régularisation)
- 💶 Suivi des paiements de loyer
- 📄 Génération de **quittances PDF** conformes loi du 6 juillet 1989
- 📤 Partage des quittances via l'API Web Share (mail, messagerie, AirDrop…)
- 📁 Stockage des documents (baux, justificatifs, états des lieux)
- 📊 Dashboard récap (loyers du mois, retards)
- 📈 Simulateur d'investissement locatif
- 📱 **PWA installable** + applications natives **iOS et Android**

## 🛠 Stack technique

| Couche | Technologie |
|---|---|
| Frontend | [Flutter](https://flutter.dev) (Dart) — Web, iOS, Android |
| State management | [Riverpod](https://riverpod.dev) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| Base de données | [Cloud Firestore](https://firebase.google.com/products/firestore) (NoSQL + Security Rules) |
| Auth | [Firebase Auth](https://firebase.google.com/products/auth) (email/password, Google, Apple, anonyme) |
| Storage | [Firebase Storage](https://firebase.google.com/products/storage) (URLs signées) |
| Backend serverless | [Cloud Functions](https://firebase.google.com/products/functions) (Node 20 + TypeScript, région `europe-west1`) |
| Génération PDF | [`pdf`](https://pub.dev/packages/pdf) (rendu côté client) |
| Partage des quittances | [`share_plus`](https://pub.dev/packages/share_plus) / Web Share API |
| Hébergement | [Firebase Hosting](https://firebase.google.com/products/hosting) |
| CI/CD | GitHub Actions |

## 🚀 Quickstart

### Prérequis

- Flutter SDK ≥ 3.41 ([guide d'install](https://docs.flutter.dev/get-started/install))
- Firebase CLI ([install](https://firebase.google.com/docs/cli))
- Node.js 20 (pour les Cloud Functions)
- GitHub CLI `gh` (optionnel, recommandé)

### Lancer en local

```bash
# 1. Installer les dépendances
flutter pub get

# 2. Copier le template de config (sélection de l'environnement)
cp dart-defines.example.json dart-defines.json
# La config Firebase elle-même vit dans lib/firebase_options.dart (versionné)
# dart-defines.json est gitignoré — ne le commit jamais

# 3. Lancer l'app sur Chrome
flutter run -d chrome --dart-define-from-file=dart-defines.json
```

Voir [`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md) pour la stratégie dev/prod.

### Build pour production

```bash
# Crée un dart-defines.prod.json pour la prod (gitignoré)
flutter build web --release --dart-define-from-file=dart-defines.prod.json
```

### Déployer

```bash
# Hosting (Flutter Web)
firebase deploy --only hosting

# Cloud Functions
cd functions && npm run build && firebase deploy --only functions

# Règles et index Firestore / Storage
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## 📂 Structure

```
EasyRent/
├── lib/                      Code Flutter (features/, core/)
├── test/                     Tests Dart
├── web/                      Assets PWA (manifest, icônes, SW)
├── android/ · ios/           Projets natifs (FEAT-024)
├── functions/
│   ├── src/callable/         Cloud Functions callables
│   ├── src/triggers/         Triggers Firestore
│   ├── src/scheduled/        Jobs planifiés
│   └── rules-tests/          Tests des règles Firestore (émulateur)
├── firestore.rules           Règles de sécurité Firestore
├── firestore.indexes.json    Index composites
├── storage.rules             Règles Firebase Storage
├── docs/
│   ├── ROADMAP.md            Roadmap MVP + post-MVP
│   ├── BACKLOG.md            Backlog ordonné
│   ├── CONVENTIONS.md        Conventions techniques
│   ├── LEGAL.md              Contraintes légales (FR)
│   ├── AGENTS.md             Pipeline d'agents IA
│   └── state/                Cache d'état projet (auto-maintenu)
└── .claude/
    ├── agents/               14 agents IA spécialisés
    ├── commands/             Slash commands d'orchestration
    └── settings.json
```

## 🤖 Développement assisté par agents IA

Ce projet utilise un pipeline d'**agents IA** ([Claude Code](https://claude.com/claude-code)) pour automatiser le cycle dev → QA → livraison.

| Commande | Effet |
|---|---|
| `/discover` | Scoute les features manquantes et crée des user stories |
| `/build-feature <id>` | Pipeline complet : design → code → QA → review → deploy staging |
| `/fix-bug <id>` | Pipeline correction de bug avec test de non-régression |
| `/qa` | Passe QA complète (tests + bug hunt + security audit) |
| `/deliver staging\|prod` | Déploie après vérifs finales |
| `/refresh-state` | Rafraîchit le cache d'état projet |

Voir [`docs/AGENTS.md`](docs/AGENTS.md) pour le détail.

## ⚖️ Conformité légale

- **Quittances** : mentions obligatoires loi du 6 juillet 1989, art. 21
- **RGPD** : consentement, export, droit à l'effacement
- **Conservation** : 5 ans minimum pour les documents fiscaux
- Détails dans [`docs/LEGAL.md`](docs/LEGAL.md)

## 🤝 Contribution

Branche par feature, PR vers `main` obligatoire, squash merge.
Conventions détaillées dans [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md).

## 📄 Licence

**Propriétaire — tous droits réservés.** Voir [`LICENSE`](LICENSE).

Ce dépôt est consultable mais n'est **pas** open source : aucun droit d'usage,
de copie, de modification ou de redistribution n'est accordé. Toute demande de
licence passe par le contact indiqué dans le fichier `LICENSE`.

# EasyRent

> Outil de gestion locative au format PWA, conçu pour les propriétaires français.

## ✨ Fonctionnalités (MVP)

- 🔐 Authentification propriétaire (email + magic link)
- 🏠 Gestion des biens immobiliers
- 👥 Gestion des locataires
- 📋 Gestion des baux (loyer, charges, durée)
- 💶 Suivi des paiements de loyer
- 📄 Génération de **quittances PDF** conformes loi du 6 juillet 1989
- 📧 Envoi automatique des quittances par email
- 📁 Stockage des documents (baux, justificatifs, états des lieux)
- 📊 Dashboard récap (loyers du mois, retards)
- 📱 **PWA installable** sur mobile et desktop

## 🛠 Stack technique

| Couche | Technologie |
|---|---|
| Frontend | [Flutter Web](https://flutter.dev) (Dart) |
| State management | [Riverpod](https://riverpod.dev) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| Base de données | [Supabase](https://supabase.com) (Postgres + RLS) |
| Auth | Supabase Auth |
| Storage | Supabase Storage (buckets privés) |
| Backend serverless | Supabase Edge Functions (Deno) |
| Génération PDF | [`pdf`](https://pub.dev/packages/pdf) + [`printing`](https://pub.dev/packages/printing) |
| Envoi emails | [Resend](https://resend.com) via Edge Function |
| Hébergement | [Firebase Hosting](https://firebase.google.com/products/hosting) |
| CI/CD | GitHub Actions |

## 🚀 Quickstart

### Prérequis

- Flutter SDK ≥ 3.41 ([guide d'install](https://docs.flutter.dev/get-started/install))
- Supabase CLI ([install](https://supabase.com/docs/guides/cli))
- Firebase CLI ([install](https://firebase.google.com/docs/cli))
- GitHub CLI `gh` (optionnel, recommandé)

### Lancer en local

```bash
# 1. Installer les dépendances
flutter pub get

# 2. Copier le template de config et remplir tes valeurs Supabase
cp dart-defines.example.json dart-defines.json
# Édite dart-defines.json avec ton URL et ta clé publishable
# (ce fichier est gitignoré — ne le commit jamais)

# 3. Lancer l'app sur Chrome
flutter run -d chrome --dart-define-from-file=dart-defines.json
```

### Build pour production

```bash
# Crée un dart-defines.prod.json pour la prod (gitignoré)
flutter build web --release --dart-define-from-file=dart-defines.prod.json
```

### Déployer

```bash
firebase deploy --only hosting
```

## 📂 Structure

```
EasyRent/
├── lib/                      Code Flutter (features/, core/)
├── test/                     Tests Dart
├── web/                      Assets PWA (manifest, icônes, SW)
├── supabase/
│   ├── migrations/           SQL versionné
│   ├── functions/            Edge Functions
│   └── tests/                Tests RLS
├── docs/
│   ├── ROADMAP.md            Roadmap MVP + post-MVP
│   ├── BACKLOG.md            Backlog ordonné
│   ├── CONVENTIONS.md        Conventions techniques
│   ├── LEGAL.md              Contraintes légales (FR)
│   ├── AGENTS.md             Pipeline d'agents IA
│   └── state/                Cache d'état projet (auto-maintenu)
└── .claude/
    ├── agents/               11 agents IA spécialisés
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

_(à définir)_

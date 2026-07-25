# EasyRent — Roadmap

## MVP — ✅ COMPLÉTÉE 2026-06-22

### Semaine 1 — Fondations
- [x] Setup Flutter Web + PWA (manifest, icônes, service worker)
- [x] Setup projet Firebase (Firestore, Auth, Storage, Functions)
- [x] ~~Auth magic link~~ → **Auth email + password (FEAT-011 pivot 2026-06-22)**
- [x] Modèle Firestore initial (landlords, properties, tenants, leases) + rules
- [x] Repo GitHub + CI minimal

### Semaine 2 — CRUD core
- [x] CRUD biens immobiliers
- [x] CRUD locataires
- [x] CRUD baux (lien bien ↔ locataire, loyer, charges, dates)
- [x] Navigation principale (drawer + routes)

### Semaine 3 — Quittances
- [x] Enregistrer un paiement de loyer
- [x] Générer quittance PDF (mentions légales conformes loi 6 juillet 1989)
- [x] Partager quittance par email (Web Share API native + fallback mailto)
- [x] Historique des quittances partagées

### Semaine 4 — Documents + dashboard + livraison
- [x] Upload et stockage de documents (Firebase Storage)
- [x] Dashboard (loyers du mois, retards, prochains baux à renouveler)
- [x] Polish PWA (offline shell, icônes, install prompt)
- [x] Déploiement prod Firebase Hosting (workflows + checklist + runbook)
- [x] Tests utilisateurs + code review

## Post-MVP M1 — ✅ COMPLÉTÉE 2026-07-05 (staging, feature-complete)

- [x] **FEAT-023** : Réglages app (thème clair/sombre + liens légaux + version)
- [x] **FEAT-025 / FEAT-025b** : Sécurité (changement mot de passe) + support in-app + hub `/profile`
- [x] **FEAT-026** : Navigation shell adaptative web+mobile (`StatefulShellRoute.indexedStack`, NavigationBar <600px / NavigationRail ≥600px). Concept : [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md)
- [x] **FEAT-027** : Dashboard — période graphique sélectionnable (6 / 12 / 24 mois)
- [x] **FEAT-028** : Détection des retards de paiement (règle métier + KPI drill-down + pastilles)
- [x] **FEAT-029 / FEAT-029b** : Charges — motif de paiement + régularisation annuelle (bail nu). V1 sans archivage.
- [x] **FEAT-030** : Navigation retour corrigée (audit QA F-1..F-4)

## En cours / imminent

- [ ] **FEAT-024 — App mobile iOS/Android (Flutter natif)** — planifiée
      semaine du 6 juillet 2026. Prérequis FEAT-026 (nav shell adaptative) ✅ livré.
      Préparation : [`docs/MOBILE.md`](MOBILE.md)

## Croissance — SEO & acquisition

- [x] **FEAT-049 — SEO du PWA (quick-wins, Option A)** — ✅ livré staging 2026-07-08
      (PR #73). `<html lang="fr">`, title/description riches en mots-clés, canonical,
      Open Graph + Twitter Card, JSON-LD (Organization / SoftwareApplication / WebSite),
      bloc HTML statique crawlable, `robots.txt` + `sitemap.xml`, **noindex staging**
      automatique. Agent `seo-specialist` + workflow `seo-audit` ajoutés au pipeline
      (phase *Growth*). Stratégie complète : [`docs/SEO.md`](SEO.md).
- [ ] **FEAT-050 — Site marketing statique crawlable (SEO Option B)** — 📋 cadré
      2026-07-08. Le rendu CanvasKit n'est pas indexable → seul un site statique séparé
      débloque le contenu crawlable par page. Topologie confirmée : sous-domaine
      `app.baillan.fr` (app Flutter inchangée, noindex) + `baillan.fr` (site **Astro**
      canonique). Démarre **après** le lancement (jamais de migration au go-live).
      Spec : [`docs/backlog/050-marketing-site-seo.md`](backlog/050-marketing-site-seo.md).

## Post-MVP P1 — backlog à prioriser

> Priorisation par le Product Owner → détail ordonné dans [`docs/BACKLOG.md`](BACKLOG.md).
> L'utilisateur décide quelles features lancer (cycle `build-feature` complet chacune).

- [ ] Rappels automatiques de paiement (Cloud Function planifiée + email)
- [ ] Export comptable (CSV / FEC)
- [ ] Multi-utilisateurs (mandataires, comptable) — permissions + invite flow
- [ ] Gestion des charges récupérables / non-récupérables
- [ ] Archivage de la régularisation de charges (FEAT-029 V2 — Cloud Function async)
- [ ] Gestion des crédits (avances, trop-perçus)
- [ ] État des lieux digital (entrée / sortie)
- [ ] Notifications push (PWA)
- [ ] Profil avancé : avatar (changement de mot de passe déjà livré via FEAT-025)
- [ ] Multi-facteur (2FA / TOTP)

## P2 (nice-to-have)

- [ ] OCR de baux scannés
- [ ] Intégration bancaire (rapprochement automatique des virements)
- [ ] ~~App native via Capacitor~~ → remplacée par FEAT-024 (Flutter cible
      iOS/Android nativement — même codebase, pas de wrapper web)
- [ ] Mode multi-propriétaires (SCI, indivision)

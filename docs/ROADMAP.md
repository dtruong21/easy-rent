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

## Post-MVP M2 — ✅ livrée sur staging (septembre–octobre 2026, release v1.1.0 « Aulne » prête)

- [x] **FEAT-024** : App mobile iOS/Android (Flutter natif, `com.daki.baillan`)
- [x] **FEAT-031 V1** : Relance de paiement assistée (côté client)
- [x] **FEAT-033** : Décompte de régularisation figé (snapshot immuable)
- [x] **FEAT-036** : Charges récupérables / non récupérables
- [x] **FEAT-037** : État des lieux digital V1 (saisie + PDF, décret 2016-382)
- [x] **FEAT-041 / FEAT-042** : Suivi des dépenses, mode de charges
- [x] **FEAT-043** : Internationalisation FR / EN
- [x] **FEAT-044 → 044d** : Freemium, gating Pro, webhook RevenueCat, Stripe Checkout web
- [x] **FEAT-045 / 046 / 047** : Suppression de compte, purge RGPD des quittances, export des données
- [x] **FEAT-054** : Isolation Firestore prod / staging (ADR 0003)
- [x] **FEAT-055** : Comparaison de scénarios (Pro)
- [x] **FEAT-058** : Onboarding progressif jusqu'à la 1re quittance
- [x] **FEAT-059** : Cartes de liste « chiffre clé » + puces de filtre
- [x] Audit OWASP du 2026-09-30 et correctifs (#208, #221), conformité App Store / Google Play (#206)

## En cours / bloqué (mis à jour le 2026-10-05)

- [ ] **Mise en prod v1.1.0** (PR #154) — recette staging validée ; **en attente de la création de la micro-entreprise** (mentions légales éditeur, Stripe).
- [ ] **FEAT-057 — Activation commerciale** (ouvrir l'abonnement Pro en prod) — bloquée par la micro-entreprise : clés Stripe live, prix live (séparation test/live prête, PR #227), checklist sur l'issue #207.
- [ ] **FEAT-044e — Achat intégré mobile (RevenueCat)** — web ✅ ; iOS/Android à faire **avant la sortie des apps** (issue #207, liste blanche sandbox pour l'App Review).
- [ ] **FEAT-056 — Paliers Max / Ultra** — grille en place, paliers non ouverts à la vente.
- [ ] **FEAT-050e — Bascule de domaine** (PR #162 : app → `app.baillan.com`, vitrine → `baillan.com`) — **en attente du DNS**.
- [ ] **Sécurité avant les stores** (issue #209) : App Check, CSP appliquée, montée `firebase-functions` / `firebase-admin`, isolation OWASP-07.
- [ ] **Sign in with Apple** — après la v1 (la v1 = Google + email ; email seul sur iOS).

## Croissance — SEO & acquisition

- [x] **FEAT-049 — SEO du PWA (quick-wins, Option A)** — ✅ livré staging 2026-07-08
      (PR #73). `<html lang="fr">`, title/description riches en mots-clés, canonical,
      Open Graph + Twitter Card, JSON-LD (Organization / SoftwareApplication / WebSite),
      bloc HTML statique crawlable, `robots.txt` + `sitemap.xml`, **noindex staging**
      automatique. Agent `seo-specialist` + workflow `seo-audit` ajoutés au pipeline
      (phase *Growth*). Stratégie complète : [`docs/SEO.md`](SEO.md).
- [ ] **FEAT-050 — Site marketing statique crawlable (SEO Option B)** — 🚧 v1
      construite (Astro, `site/`), en attente de la bascule de domaine. Cadré
      2026-07-08. Le rendu CanvasKit n'est pas indexable → seul un site statique séparé
      débloque le contenu crawlable par page. Topologie confirmée : sous-domaine
      `app.baillan.fr` (app Flutter inchangée, noindex) + `baillan.fr` (site **Astro**
      canonique). Démarre **après** le lancement (jamais de migration au go-live).
      Spec : [`docs/backlog/050-marketing-site-seo.md`](backlog/050-marketing-site-seo.md).

## Post-MVP P1 — backlog à prioriser

> Priorisation par le Product Owner → détail ordonné dans [`docs/BACKLOG.md`](BACKLOG.md).
> L'utilisateur décide quelles features lancer (cycle `build-feature` complet chacune).

- [ ] **Rappels automatiques de paiement par email** (FEAT-031 V2, cron) — prérequis :
      issue #129 (politique anti-usurpation de `baillan.com`)
- [ ] Export comptable (CSV / FEC)
- [ ] Multi-utilisateurs (mandataires, comptable) — permissions + invite flow
- [ ] Gestion des crédits (avances, trop-perçus) (FEAT-039)
- [ ] Notifications push (FEAT-038)
- [ ] Profil avancé : avatar (FEAT-040 ; changement de mot de passe déjà livré via FEAT-025)
- [ ] Multi-facteur (2FA / TOTP) (FEAT-035, 📋 planned)
- [ ] Annonces & diffusion multi-portails (FEAT-051, 💡 idée)
- [x] ~~Charges récupérables / non récupérables~~ → FEAT-036 ✅
- [x] ~~Archivage de la régularisation de charges~~ → FEAT-033 ✅
- [x] ~~État des lieux digital~~ → FEAT-037 V1 ✅
- [x] ~~Import CSV~~ → FEAT-034 abandonné (décision PM 2026-09-14)

## P2 (nice-to-have)

- [ ] OCR de baux scannés
- [ ] Intégration bancaire (rapprochement automatique des virements)
- [ ] ~~App native via Capacitor~~ → remplacée par FEAT-024 (Flutter cible
      iOS/Android nativement — même codebase, pas de wrapper web)
- [ ] Mode multi-propriétaires (SCI, indivision)

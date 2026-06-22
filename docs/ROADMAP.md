# EasyRent — Roadmap

## MVP — ✅ COMPLÉTÉE 2026-06-22

### Semaine 1 — Fondations
- [x] Setup Flutter Web + PWA (manifest, icônes, service worker)
- [x] Setup Supabase projet (dev + prod)
- [x] ~~Auth Supabase (magic link)~~ → **Auth email + password (FEAT-011 pivot 2026-06-22)**
- [x] Schéma DB initial (landlords, properties, tenants, leases) + RLS
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
- [x] Upload et stockage de documents (Supabase Storage)
- [x] Dashboard (loyers du mois, retards, prochains baux à renouveler)
- [x] Polish PWA (offline shell, icônes, install prompt)
- [x] Déploiement prod Firebase Hosting (workflows + checklist + runbook)
- [x] Tests utilisateurs + code review

## Post-MVP — P1

- [ ] **FEAT-012** : Password change endpoint + profil utilisateur
- [ ] **FEAT-013** : Rappels automatiques de paiement (cron Edge Function)
- [ ] **FEAT-014** : Export comptable (CSV / FEC)
- [ ] **FEAT-015** : Multi-utilisateurs (mandataires, comptable)
- [ ] Gestion des charges récupérables / non-récupérables
- [ ] Gestion des crédits (avances, trop-perçus)
- [ ] Régularisation annuelle des charges
- [ ] État des lieux digital (entrée/sortie)
- [ ] Notifications push (PWA)
- [ ] Multi-facteur (2FA / TOTP)

## P2 (nice-to-have)

- [ ] OCR de baux scannés
- [ ] Intégration bancaire (rapprochement automatique des virements)
- [ ] App native via Capacitor
- [ ] Mode multi-propriétaires (SCI, indivision)

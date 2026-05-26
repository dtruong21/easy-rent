# EasyRent — Roadmap

## MVP (4 semaines)

### Semaine 1 — Fondations
- [ ] Setup Flutter Web + PWA (manifest, icônes, service worker)
- [ ] Setup Supabase projet (dev + prod)
- [ ] Auth Supabase (signup, login, magic link)
- [ ] Schéma DB initial (landlords, properties, tenants, leases) + RLS
- [ ] Repo GitHub + CI minimal

### Semaine 2 — CRUD core
- [ ] CRUD biens immobiliers
- [ ] CRUD locataires
- [ ] CRUD baux (lien bien ↔ locataire, loyer, charges, dates)
- [ ] Navigation principale (drawer + routes)

### Semaine 3 — Quittances
- [ ] Enregistrer un paiement de loyer
- [ ] Générer quittance PDF (mentions légales conformes loi 6 juillet 1989)
- [ ] Envoyer quittance par email (Resend via Edge Function)
- [ ] Historique des quittances envoyées

### Semaine 4 — Documents + dashboard + livraison
- [ ] Upload et stockage de documents (Supabase Storage)
- [ ] Dashboard (loyers du mois, retards, prochains baux à renouveler)
- [ ] Polish PWA (offline shell, icônes, install prompt)
- [ ] Déploiement prod Firebase Hosting
- [ ] Tests utilisateurs

## Post-MVP — P1

- [ ] Gestion des charges récupérables / non-récupérables
- [ ] Gestion des crédits (avances, trop-perçus)
- [ ] Régularisation annuelle des charges
- [ ] État des lieux digital (entrée/sortie)
- [ ] Rappels automatiques de paiement (cron Edge Function)
- [ ] Export comptable (CSV / FEC)
- [ ] Multi-utilisateurs (mandataires, comptable)
- [ ] Notifications push (PWA)

## P2 (nice-to-have)

- [ ] OCR de baux scannés
- [ ] Intégration bancaire (rapprochement automatique des virements)
- [ ] App native via Capacitor
- [ ] Mode multi-propriétaires (SCI, indivision)

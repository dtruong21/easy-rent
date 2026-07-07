# EasyRent — Backlog

Géré par `product-owner` et `feature-scout`. Détails dans `docs/backlog/<id>-<slug>.md`.

> Dernière mise à jour : 2026-07-05 (Priorisation Post-MVP P1 — 10 items RICE, décision utilisateur attendue)

## En cours

| ID | Titre | Statut | Doc |
|---|---|---|---|
| FEAT-026 | Navigation shell adaptative web+mobile | ✅ Implémenté + staging 2026-07-03 (commit ca2d10a) — décisions validées : 5 onglets, Profil en onglet, avant la semaine mobile | [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md) |
| FEAT-024 | App mobile iOS/Android (Flutter natif) | 🟡 Préparée — dev semaine du 6 juillet 2026 (dépend de FEAT-026 pour la nav) | [`docs/MOBILE.md`](MOBILE.md) (audit portabilité + décisions + plan semaine) |
| FEAT-025 | Écran Profil → vrai paramétrage (password change, contact support) | ✅ Livré staging 2026-07-03 (commits f5734b4 + 0cd54de) — reste : notif email (extension Trigger Email, runbook dans la story) | [`backlog/025-settings-profile.md`](backlog/025-settings-profile.md) |
| FEAT-028 | Détection et affichage des retards de paiement (correction KPI dashboard) | 📋 Spec'd 2026-07-04 — décisions ouvertes : délai de grâce (5j proposé), proratisation 1er mois | [`backlog/028-retards-paiement.md`](backlog/028-retards-paiement.md) |

## Prochain (P0 — MVP, chaîne bloquante)

Ordonnées par dépendance. FEAT-003 et FEAT-004 sont parallélisables une fois FEAT-002 mergée.

| Ordre | ID | Titre | Dépend de | Story |
|---|---|---|---|---|
| 1 | FEAT-011 | Authentification email + password (pivot FEAT-001) | — | ✅ Implémentée 2026-06-22, voir `docs/plans/FEAT-011-auth-password.md` |
| 2 | FEAT-002 | Modèle de données & RLS (`landlords`, `properties`, `tenants`, `leases`) | FEAT-001 | [`backlog/002-data-model-rls.md`](backlog/002-data-model-rls.md) |
| 3 | FEAT-003 | CRUD biens immobiliers | FEAT-002 | [`backlog/003-crud-properties.md`](backlog/003-crud-properties.md) |
| 3 | FEAT-004 | CRUD locataires | FEAT-002 | [`backlog/004-crud-tenants.md`](backlog/004-crud-tenants.md) |
| 4 | FEAT-005 | CRUD baux (bien ↔ locataire) | FEAT-003, FEAT-004 | [`backlog/005-crud-leases.md`](backlog/005-crud-leases.md) |

```
FEAT-001 (auth)
    └── FEAT-002 (schéma + RLS)        ← fondation
            ├── FEAT-003 (properties)  ┐ parallélisables
            ├── FEAT-004 (tenants)     ┘
                    └── FEAT-005 (leases)
```

### Suite MVP — Complétée 2026-06-22

- ✅ Navigation principale (drawer + routes)
- ✅ FEAT-008 — Partager quittance par email (Web Share API native) → `docs/plans/FEAT-008-email-quittance.md`
- ✅ FEAT-009 — Upload & stockage de documents (Supabase Storage) → `docs/plans/FEAT-009-documents-storage.md`
- ✅ FEAT-010 — Dashboard + polish PWA + déploiement prod → [`backlog/010-dashboard-pwa-prod-setup.md`](backlog/010-dashboard-pwa-prod-setup.md)

### Stories détaillées (P0 — à implémenter)

| Ordre | ID | Titre | Dépend de | Status |
|---|---|---|---|---|
| 6 | FEAT-006 | Enregistrer un paiement de loyer | FEAT-005 | ✅ Done |
| 7 | FEAT-007 | Générer une quittance PDF de loyer (loi 6 juillet 1989) | FEAT-006 | ✅ Done |
| 8 | FEAT-008 | Partager une quittance par email (Web Share API native) | FEAT-007 | ✅ Done (pivot 2026-06-22) |
| 9 | FEAT-009 | Upload & stockage de documents (Supabase Storage) | FEAT-005 | ✅ Done |
| 10 | FEAT-010 | Dashboard + PWA polish + Prod setup | FEAT-009 | ✅ Done |
| 11 | FEAT-011 | Auth email + password (pivot FEAT-001) | — | ✅ Done |

**Post-MVP (FEAT-012+)** :
- FEAT-012 : Password change endpoint + profil utilisateur
- FEAT-013 : Email rappels automatiques de paiement (cron Edge Function)
- FEAT-014 : Export comptable (CSV / FEC)

## Dette technique / risques identifiés (scout 2026-05-27)

- ✅ ~~`test/` absent~~ → résolu : scaffold `test/unit` + `test/widget` + étape `build_runner` ajoutée à la CI.
- ✅ ~~Pas de suite de tests RLS~~ → entamé : `supabase/tests/rls_landlords.sql` (à étendre par table au fil de FEAT-002+).
- **Aucun bucket Storage** configuré → bloque FEAT-009. À provisionner avant.
- **Aucune Edge Function** (`supabase/functions/` vide) → bloque FEAT-008 (Resend). Choisir le domaine email vérifié avant.
- **Pas de `seed.sql`** → données de dev locales manuelles pour l'instant.

### Setup infra déploiement — staging OK, prod à finir
- ✅ ~~`firebase.json` / `.firebaserc`~~ → posés (`build/web` + rewrites SPA pour GoRouter).
- ✅ ~~Secrets staging~~ : `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID` → posés sur env `staging`.
- ✅ ~~Provisionnement schéma `dev` pour QA staging~~ → fait via Supabase CLI (`supabase db push`).
- ✅ ~~Service worker piège-cache sur staging~~ → désactivé via `--pwa-strategy=none` dans `deploy.yml` quand env=staging.
- 🔧 **Environnement GitHub `production` à créer** (seul `staging` existe).
- 🔧 **Secrets prod manquants** : dupliquer `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_PROJECT_ID` sur env `production`. Plus ajouter `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` (utilisés par le job `apply-supabase-migrations` qui ne tourne que depuis `main`).
- 🔧 **Stratégie d'apply migrations à automatiser** : actuellement migrations posées sur dev via CLI manuelle. À terme : soit étendre `deploy.yml` pour appliquer aussi depuis `develop`, soit garder l'approche "1 fois par release depuis `main`". À trancher pendant FEAT-002.

### Gates AVANT mise en PROD (issus de l'audit sécu FEAT-001)
- ✅ ~~Redirect Allow-List Supabase~~ → configurée (Site URL + 3 variantes de redirect URLs pour staging, à ajouter pour prod plus tard).
- 🔧 **Compléter `/privacy`** : identité du responsable de traitement, DPO, base légale définitive de la persistance de session (placeholder actuellement).
- 🔧 **Seuils de rate-limit OTP** Supabase à vérifier en Studio.
- 🔧 **Reproduire URL Configuration Supabase pour le canal `live`** quand on déploiera en prod (Site URL + Redirect Allow-List).

### Items résolus par FEAT-002
- ✅ ~~FK `landlords.id … ON DELETE CASCADE`~~ → remplacé par `ON DELETE NO ACTION` (rétention 5 ans garantie). L'effacement RGPD passera par Edge Function dédiée (P1 ci-dessous).
- ✅ ~~Restriction colonne `deleted_at`~~ → trigger `prevent_protected_columns_change` (BEFORE INSERT OR UPDATE) sur 4 tables × 2 schémas ; soft-delete passe par RPC `soft_delete_*` SECURITY DEFINER.

### Dette tracée par FEAT-002 (P1)
- **Hardening flag de session GUC** : `app.allow_deleted_at_change` est aujourd'hui safe (PostgREST n'expose pas `set_config`) mais reste un footgun architectural. Remplacer par un mécanisme intransférable (ex: `pg_trigger_depth()` test, ou wrapping en fonction SECURITY DEFINER de niveau supérieur). Cf section "⚠️ Patterns sensibles" dans `docs/SECURITY.md`.
- **RGPD self-service** (P1) : export des données + droit à l'effacement (Edge Function qui anonymise plutôt qu'efface, conforme rétention 5 ans + RPC `soft_delete_*` cascade enfants).
- **`soft_delete_landlord` ne cascade pas vers properties/tenants/leases** : aujourd'hui un landlord soft-deleted laisse ses enfants visibles (deleted_at=NULL). Conforme RGPD rétention, mais incohérent UX si restauration future. À documenter ou à ajuster en P1.

## Post-MVP immédiat (P1 — prochaine itération)

| ID | Titre | Dépend de | Story | Effort |
|---|---|---|---|---|
| FEAT-017 | Rentabilité portfolio — rendement brut/net + cash-flow | FEAT-003, FEAT-005, FEAT-006, FEAT-010, FEAT-014 | [`backlog/017-portfolio-rentability.md`](backlog/017-portfolio-rentability.md) | L (3 phases ~5-7j) |
| FEAT-018 | Simulateur d'investissement locatif (page `/simulator`, scénarios sauvegardables, comparaison 3 scénarios) | FEAT-002, FEAT-011 | [`backlog/018-investment-simulator.md`](backlog/018-investment-simulator.md) | L (4 sprints ~5-7j) |

## Plus tard (P1, P2)

| ID | Titre | Story | Statut |
|---|---|---|---|
| FEAT-029 | Charges copropriété exceptionnelles + régularisation annuelle des charges | [`backlog/029-charges-regularisation.md`](backlog/029-charges-regularisation.md) | 📋 Cadré (2026-07-03) — scope V1 réduit (bail nu, doc `documents` réutilisé), décisions ouvertes avant chiffrage, risque `firestore.rules`/`functions/` signalé |
| FEAT-041 | Dépenses — entité first-class (CRUD + catégorisation + justificatif + alimentation régularisation) | [`backlog/041-depenses.md`](backlog/041-depenses.md) | 📋 Cadré (2026-07-05) — absorbe FEAT-033 (archivage régularisation) ; V1.1 = rentabilité sur dépenses réelles (FEAT-017) ; 7 décisions produit ouvertes avant chiffrage |
| FEAT-046 | Purge différée des quittances archivées (RGPD art. 5.1.e) — cron quotidien qui hard-delete les `receipts` avec `retentionUntil <= now` (stampées par `deleteAccount`, FEAT-045). Honore la promesse « puis supprimées à l'échéance » de la privacy policy v1.2. Effort S (pattern `cleanupExpiredAnon` + index composite `retentionUntil`) | — | 📋 Suivi audit FEAT-045 (L1, 2026-07-07) — horizon 5 ans, non urgent |
| FEAT-047 | Export des données (RGPD art. 15/20 — droit d'accès + portabilité) : callable `exportAccountData` (JSON/CSV de toutes les collections du landlord) + bouton Profil. Gap relevé par l'audit FEAT-045 (docs/LEGAL.md promettait déjà `GET /export`) | — | 📋 Suivi audit FEAT-045 (2026-07-07) |

---

## Priorisation Post-MVP P1 (2026-07-05) — décision utilisateur attendue

> **Contexte** : MVP + Post-MVP M1 (FEAT-001→030) feature-complete staging. FEAT-024 (app mobile
> Flutter natif) mobilise l'équipe la semaine du 6 juillet 2026 — même codebase web+mobile, donc
> tout chantier touchant navigation/formulaires/CF partagés cette semaine-là crée un risque de
> conflit de merge. Priorisation ci-dessous pour que l'utilisateur choisisse quoi lancer en
> `build-feature` complet, une fois FEAT-024 stabilisée ou en parallèle si le risque est jugé acceptable.
>
> **Méthode** : RICE (Reach × Impact × Confidence ÷ Effort), échelle 1–5 sur R/I/C, Effort en
> jours-équivalents. Reach/Impact estimés qualitativement (produit encore en staging, pas de
> données d'usage prod réelles) — à recalibrer avec des métriques réelles après premiers
> utilisateurs payants.
>
> **Réconciliation ID** : `docs/state/INDEX.md` avait pré-annoncé FEAT-031 (rappels),
> FEAT-033 (archivage régul.) et FEAT-035 (2FA) sur des sujets identiques aux items #1, #5, #10
> ci-dessous — IDs conservés tels quels. FEAT-032/034 (« Trésorerie »/« Import CSV » dans
> INDEX.md) n'étaient que des idées non spec'd et sont réattribués aux items #2 et #3 ci-dessous
> (Export FEC, Multi-utilisateurs). Nouveaux IDs FEAT-036→040 pour le reste. `state-keeper` devra
> resynchroniser `INDEX.md` en conséquence à la prochaine passe.

### Classement RICE

| Rang | ID | Feature | R | I | C | Effort (j) | Score RICE |
|---|---|---|---|---|---|---|---|
| 1 | FEAT-031 | Rappels automatiques de paiement | 5 | 4 | 5 | 2 | **50** |
| 2 | FEAT-036 | Charges récupérables / non-récupérables | 4 | 3 | 5 | 2 | **30** |
| 3 | FEAT-033 | Archivage régularisation charges (FEAT-029 V2) | 3 | 3 | 5 | 2 | **22.5** |
| 4 | FEAT-032 | Export comptable CSV / FEC | 3 | 3 | 4 | 3 | **12** |
| 5 | FEAT-040 | Profil avancé — avatar | 5 | 1 | 5 | 0.5 | **10** |
| 6 | FEAT-035 | Multi-facteur (2FA / TOTP) | 2 | 3 | 4 | 3 | **8** |
| 7 | FEAT-034 | Multi-utilisateurs (mandataires, comptable) | 2 | 4 | 3 | 4 | **6** |
| 7 | FEAT-038 | Notifications push (PWA) | 3 | 3 | 2 | 3 | **6** |
| 7 | FEAT-039 | Gestion des crédits (avances, trop-perçus) | 2 | 3 | 3 | 3 | **6** |
| 10 | FEAT-037 | État des lieux digital (entrée / sortie) | 3 | 4 | 2 | 5 | **4.8** |

**Rationale par rang** :

1. **FEAT-031 — Rappels automatiques** : plus haut Reach (tout bailleur avec un locataire en
   retard, situation fréquente) × plus haut Impact (résout la douleur n°1 identifiée dès FEAT-028)
   × Confidence maximale (Cloud Function planifiée + email = pattern déjà maîtrisé, proche de
   `cleanupExpiredAnon`) pour un effort faible. Meilleur ratio du backlog.
2. **FEAT-036 — Charges récupérables/non-récupérables** : Reach élevé (bail nu = majorité du
   parc géré), synergise directement avec FEAT-029 (régularisation) déjà livrée — sans cette
   distinction, la régularisation actuelle reste approximative légalement. Effort faible car
   étend un modèle de données existant (`leases.charges`) plutôt que d'en créer un nouveau.
3. **FEAT-033 — Archivage régularisation V2** : dette technique déjà tracée et documentée
   (FEAT-029 V1 « PAS d'archivage »), Confidence maximale (scope déjà borné par la V1). Complète
   une feature à moitié livrée plutôt que d'en ouvrir une nouvelle — rentable.
4. **FEAT-032 — Export FEC** : Reach moyen (surtout utile en fin d'année fiscale / déclaration
   revenus fonciers), mais Confidence bonne (format réglementé donc spec exhaustive possible).
   Bloqué par la nécessité de valider le format FEC exact avec le cadre DGFiP avant chiffrage.
5. **FEAT-040 — Avatar** : Reach large mais Impact quasi nul (cosmétique pur, aucune douleur
   métier). Remonte seulement par son effort dérisoire (quick win) — à ne lancer qu'en filler
   entre deux chantiers plus lourds, jamais en priorité isolée.
6. **FEAT-035 — 2FA/TOTP** : Reach faible (profil sécurité = minorité des utilisateurs y pense
   spontanément), mais Impact réel pour la confiance/rétention sur un produit qui manipule des
   données locataires sensibles. Non urgent tant qu'aucun incident de sécurité ne le justifie.
7. **FEAT-034 / FEAT-038 / FEAT-039** (ex-æquo score 6) : trois features à Impact correct mais
   pénalisées soit par un Reach de niche (multi-utilisateurs = surtout mandataires/agences, pas
   le bailleur particulier isolé — cœur de cible EasyRent), soit par une Confidence basse
   (notifications push PWA = fiabilité iOS Safari historiquement incertaine ; gestion des
   crédits = cas d'usage encore flou, à cadrer avant chiffrage).
10. **FEAT-037 — État des lieux digital** : Impact potentiellement fort (photos, signature,
    conformité décret 2016-382) mais Confidence la plus basse du lot (feature riche UI/upload,
    plusieurs sous-écrans, pas de brique existante à réutiliser) et Effort le plus élevé. Bon
    candidat mobile-first (photos in-situ) mais à cadrer plus finement avant de chiffrer une
    L définitive — actuellement en position basse faute de maturité de la spec, pas faute
    de valeur perçue.

### Recommandation de séquence

**TOP 3 à lancer en premier, dans cet ordre** : FEAT-031 → FEAT-036 → FEAT-033.

Les trois partagent un profil bas risque pendant la semaine mobile (S/M, logique métier +
Cloud Functions backend, aucun n'impose de refonte d'écran de navigation/formulaire partagé
avec le shell adaptatif que FEAT-024 mobilise) et complètent des chantiers déjà entamés
(FEAT-028 retards, FEAT-029 régularisation) plutôt que d'ouvrir un nouveau front produit.
FEAT-032 (Export FEC) est un bon 4ème choix mais nécessite une clarification préalable du
format réglementaire — à cadrer en parallèle pendant que FEAT-031/036/033 se développent, pas
à lancer en `build-feature` avant d'avoir cette réponse. FEAT-040 (avatar) peut être glissé en
filler d'une demi-journée entre deux chantiers, mais ne mérite pas un slot dédié.

**À éviter cette semaine (conflit avec FEAT-024)** : toute story qui touche formulaires
partagés, écrans profil ou navigation shell — donc différer FEAT-034 (invite flow = nouveaux
écrans + nouvelles routes) et FEAT-037 (état des lieux = nouveaux écrans riches) jusqu'à
stabilisation de FEAT-024, même si leur score RICE remontait après cadrage.

### Détail des stories (TOP 4)

#### FEAT-031 — Rappels automatiques de paiement

**User story** : En tant que bailleur, je veux être alerté automatiquement quand un loyer
n'est pas payé à l'échéance afin de relancer mon locataire sans avoir à vérifier manuellement
mon dashboard chaque mois.

**Légal/conformité** : email de relance = communication entre bailleur et locataire, pas de
mention RGPD spécifique au-delà des mentions email standard ([`docs/LEGAL.md`](LEGAL.md) —
nom du responsable de traitement + lien désabonnement si non-transactionnel). Attention :
ne pas confondre relance (information) et mise en demeure (acte juridique formel) — la
relance automatique ne doit pas se substituer à une procédure de recouvrement.

**Dépendances techniques** : réutilise `lease_lateness.dart` (FEAT-028, déjà testé) comme
détecteur. Nouvelle Cloud Function scheduled (pattern `cleanupExpiredAnon`) + extension
Trigger Email (déjà évoquée FEAT-025 V2 pour `support_requests` — même brique reprise ici).
Pas de nouvelle collection Firestore nécessaire a priori (lecture `leases` + `payments`
existants) ; à confirmer si un flag `lastReminderSentAt` doit être ajouté à `leases` pour
éviter les relances en double (probable — impact schema mineur).

**Synergie mobile** : neutre. Feature 100% backend (Cloud Function + email), aucun écran à
construire, zéro conflit avec le chantier FEAT-024.

**Acceptance criteria (extrait)** :
- **Given** un bail actif avec un paiement en retard (règle `isLeaseLate()`) **When** la
  Cloud Function planifiée s'exécute **Then** un email de relance est envoyé au locataire
  et un flag anti-doublon est posé.
- **Given** un locataire déjà relancé cette échéance **When** la fonction planifiée
  s'exécute à nouveau **Then** aucun second email n'est envoyé pour la même période.

---

#### FEAT-036 — Charges récupérables / non-récupérables

**User story** : En tant que bailleur, je veux distinguer les charges récupérables des
charges non-récupérables sur mon bail afin que ma régularisation annuelle et mes quittances
reflètent la répartition légale réelle (décret n°87-713).

**Légal/conformité** : décret n°87-713 du 26 août 1987 fixe la liste limitative des charges
récupérables (entretien parties communes, taxe ordures ménagères, etc.). Une régularisation
qui ne fait pas cette distinction est juridiquement contestable par le locataire. Impact
direct sur la conformité de FEAT-029 (régularisation annuelle) déjà livrée en V1.

**Dépendances techniques** : étend `leases.charges` (actuellement un seul montant en
centimes) — probable split en deux champs ou sous-map (`charges.recoverable` /
`charges.nonRecoverable`) côté `leases` et `payments`. Impacte `charge_regularization/**`
(FEAT-029) qui devra ventiler le calcul. Pas de nouvelle collection ; migration de champ
existant (attention : `leases` est CF-exclusive, donc migration via callable `updateLease`
ou script one-shot Admin SDK).

**Synergie mobile** : neutre à légèrement positif — évolution de formulaire (LeaseFormPage/
LeaseEditPage) déjà partagée web+mobile, aucun écran mobile-spécifique à créer, mais touche
un formulaire existant → tester sur les deux form factors avant merge si FEAT-024 est déjà
avancée.

**Acceptance criteria (extrait)** :
- **Given** la création/édition d'un bail **When** le bailleur saisit les charges **Then**
  il renseigne séparément le montant récupérable et non-récupérable.
- **Given** une régularisation annuelle (FEAT-029) **When** le calcul du solde s'exécute
  **Then** seules les charges récupérables entrent dans le solde régularisable.

---

#### FEAT-033 — Archivage de la régularisation de charges (FEAT-029 V2)

**User story** : En tant que bailleur, je veux que mes régularisations de charges passées
soient conservées et consultables afin de retrouver l'historique en cas de litige ou de
contrôle, sans avoir à régénérer le calcul.

**Légal/conformité** : les régularisations de charges sont des documents à valeur probante
en cas de litige locatif — même logique de rétention que les quittances
([`docs/LEGAL.md`](LEGAL.md), 5 ans minimum). V1 actuelle ne persiste pas le résultat,
seulement `lease.chargeRegularizationHistory` en map optionnelle côté client — pas
d'immuabilité garantie.

**Dépendances techniques** : nouvelle collection `charge_regularizations/{id}` (pattern
`receipts` — CF-exclusive, immuable, pas de soft-delete) + Cloud Function callable
`createChargeRegularization` (déplace le calcul aujourd'hui client-side vers Admin SDK pour
garantir l'intégrité) + éventuel stockage PDF Storage (réutilise le renderer déjà écrit :
`charge_regularization_pdf_renderer.dart`). Nécessite indexes composites (landlordId,
leaseId, periodStart).

**Synergie mobile** : neutre. Chantier backend (Cloud Function + Firestore), le rendu PDF
existant est déjà portable (pdf + printing, confirmé par l'audit FEAT-024 dans
[`docs/MOBILE.md`](MOBILE.md)).

**Acceptance criteria (extrait)** :
- **Given** une régularisation de charges validée par le bailleur **When** il confirme
  l'avis récapitulatif **Then** un document immuable est créé dans
  `charge_regularizations` avec son PDF associé, non modifiable ensuite.
- **Given** une fiche bail avec régularisations passées **When** le bailleur consulte
  l'historique **Then** il retrouve chaque régularisation archivée avec son PDF.

---

#### FEAT-032 — Export comptable (CSV / FEC)

**User story** : En tant que bailleur, je veux exporter mes revenus locatifs et charges
dans un format comptable standard afin de simplifier ma déclaration de revenus fonciers ou
la transmission à mon comptable.

**Légal/conformité** : le format FEC (Fichier des Écritures Comptables) est un format
réglementé par la DGFiP (obligatoire pour les entreprises soumises à un contrôle fiscal
informatisé — art. L47 A du LPF). **Décision produit à trancher avant chiffrage** : un
bailleur particulier (régime micro-foncier ou réel) n'est pas nécessairement soumis à
l'obligation FEC stricto sensu — un export CSV simple (type tableau récapitulatif loyers/
charges par bien/par an) peut suffire à l'usage réel visé (déclaration 2044) sans s'engager
sur la structure FEC complète (18 colonnes normées, JournalCode, EcritureNum, etc.). À
clarifier avec l'utilisateur avant de lancer le `build-feature`.

**Dépendances techniques** : nouvelle Cloud Function callable `exportAccounting` (lecture
`payments` + `leases` + `properties` sur une période, génération CSV) — pas de nouvelle
collection. Si format FEC retenu : contrainte de nommage de fichier réglementaire
(SIREN + FEC + date de clôture) sans objet direct pour un particulier sans SIREN, autre
signal que le CSV simple est probablement le bon niveau de scope.

**Synergie mobile** : neutre. Export déclenché depuis un écran existant (dashboard ou fiche
bien), résultat = téléchargement fichier — sur mobile, passera par `share_plus`/
`Printing`-like plutôt que `dart:html` download (déjà le pattern retenu pour les quittances
mobile selon [`docs/MOBILE.md`](MOBILE.md)).

**Acceptance criteria (extrait)** :
- **Given** un bailleur sur son dashboard **When** il demande un export comptable pour une
  année **Then** il reçoit un fichier CSV listant loyers encaissés et charges par bien et
  par mois.
- **Given** un export en cours de génération **When** la période demandée ne contient aucun
  paiement **Then** un fichier vide avec en-têtes est produit (pas d'erreur).

---

Voir aussi [`docs/ROADMAP.md`](ROADMAP.md) — crédits, état des lieux digital, notifications
push PWA, OCR, intégration bancaire (items non détaillés ci-dessus, restent au backlog P1/P2
tel quel selon le classement RICE).

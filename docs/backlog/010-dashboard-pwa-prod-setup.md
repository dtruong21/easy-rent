# [FEAT-010] Dashboard + Polish PWA + Déploiement prod

## User story

En tant que **propriétaire bailleur**, je veux **voir d'un coup d'oeil les indicateurs clés de ma gestion locative, installer l'application sur mon appareil, et accéder à l'app en production** afin de **piloter mon parc sans devoir naviguer dans chaque section et utiliser EasyRent comme outil du quotidien**.

## Context & motivation

C'est la dernière feature avant le 1er déploiement en production. Elle cumule 3 concerns distincts :

- **A. Dashboard** : L'écran d'accueil actuel n'est qu'un menu de 3 ListTile. Un propriétaire qui ouvre l'app veut savoir immédiatement : ai-je des loyers en retard ? Est-ce que mes quittances du mois sont générées ? Un bail expire-t-il bientôt ? Cette page doit devenir le cockpit de la gestion locative.
- **B. Polish PWA** : L'app est déclarée PWA mais le service worker, le manifest et les icônes utilisent les valeurs Flutter par défaut. Une PWA sans icône personnalisée ni install prompt ne donne pas confiance à l'utilisateur.
- **C. Setup prod** : L'environnement GitHub `production` n'existe pas encore, les secrets prod sont manquants, les migrations ne sont pas automatisées sur le schéma `public`, et la page `/privacy` est incomplète. Sans ces éléments, le 1er deploy est bloqué.

Ces 3 axes sont à implémenter dans cet ordre (C bloque le go-live, A et B peuvent avancer en parallèle).

---

## Décisions à prendre (D1–D5)

Ces décisions doivent être tranchées AVANT l'implémentation. Defaults raisonnables proposés ci-dessous.

| # | Question | Default proposé | Raison |
|---|---|---|---|
| D1 | Dashboard : 4 KPI ou commencer par 2 (loyers + retards) ? | **4 KPI** : loyers du mois, retards, baux à renouveler (30j), raccourci "Générer quittances" | 4 KPI restent simples à implémenter avec des requêtes SQL directes |
| D2 | Charts : mini-barchart "encaissé / dû" mensuel ou text-only ? | **Text-only MVP** — barchart en P1 (FEAT-011 ou refonte visuelle) | Évite d'ajouter une dépendance chart et du scope. La mémoire utilisateur indique la vision financial dashboard comme post-MVP. |
| D3 | PWA install prompt : 2e visite ou 1er login ? | **1er login réussi** — dismiss persistant en `SharedPreferences` | Plus naturel que 2e visite, évite de montrer le prompt avant que l'utilisateur ait vu de la valeur |
| D4 | Icônes PWA : placeholder "ER" texte sur fond teal ou attendre un design ? | **Placeholder "ER"** sur `#0F766E` — icônes 192px et 512px générées programmatiquement | Débloque le go-live ; une icône custom sera P1 |
| D5 | Migrations prod : (a) manuelle, (b) CI auto, (c) workflow_dispatch avec confirmation ? | **(c) workflow_dispatch** — déclenchement manuel depuis l'UI GitHub, avec confirmation explicite | Évite les migrations auto qui pourraient casser prod silencieusement ; préserve le contrôle |

---

## Périmètre — sous-features A, B, C

### A. Dashboard — Refonte page d'accueil

**Page concernée** : `lib/features/dashboard/presentation/dashboard_page.dart`

**Ce que cette sous-feature produit :**

1. **KPI cards** en haut de page (4 cartes) :
   - "Loyers ce mois" : montant encaissé vs. montant dû (SUM `payments.total_amount_cents` WHERE `paid_at` dans le mois courant, vs. SUM `leases.rent_amount_cents + charges_amount_cents` des baux actifs)
   - "Locataires en retard" : nombre de baux actifs sans paiement enregistré pour le mois courant
   - "Baux à renouveler" : baux avec `end_date BETWEEN now() AND now() + interval '30 days'`
   - "Documents en attente" : count des documents avec `status = 'pending'` (optionnel, masquer la carte si FEAT-009 non encore déployée)

2. **Section "Activité récente"** : 5 dernières entrées toutes catégories confondues (paiements, quittances générées, documents uploadés), triées par `created_at DESC`. Chaque entrée est cliquable et navigue vers le détail.

3. **Shortcuts de navigation** : Les 3 tuiles actuelles (Mes biens / Mes locataires / Mes baux) sont conservées mais redessinées en petites tuiles compactes sous les KPI.

4. **Écran "Premiers pas" (onboarding)** : Si et seulement si `properties.count = 0 AND tenants.count = 0 AND leases.count = 0`, afficher une checklist guidée à la place des KPI. Les items de la checklist sont : (1) Ajouter un bien, (2) Ajouter un locataire, (3) Créer un bail. Chaque item est un bouton qui navigue vers la page de création correspondante.

5. **Layout responsive** : Sur écran large (> 900px), les 4 KPI cards s'affichent en grille 4 colonnes. Sur mobile, en liste verticale 1 colonne.

**Sources de données** : requêtes agrégées depuis `DashboardRepository` (nouveau fichier), pas de cache serveur — les données sont fetchées à chaque visite de la page. Les requêtes utilisent le schéma courant (`public` en prod, `dev` en staging) via l'env dart-define `SUPABASE_SCHEMA`.

**Amorce vision financial dashboard (mémoire utilisateur)** : Le layout et les composants `KpiCard` doivent être conçus pour évoluer vers des charts en P1. La `KpiCard` doit accepter un slot `child` optionnel pour accueillir un widget chart sans refonte. Ne pas implémenter les charts maintenant.

---

### B. Polish PWA

**Ce que cette sous-feature produit :**

1. **manifest.json** : Auditer et corriger `web/manifest.json` —
   - `name` : "EasyRent"
   - `short_name` : "EasyRent"
   - `theme_color` : `#0F766E`
   - `background_color` : `#0F766E`
   - `display` : `standalone`
   - `start_url` : `/`

2. **Icônes PWA** : Remplacer les icônes Flutter par défaut dans `web/icons/` par des icônes "ER" sur fond teal (voir D4). Icônes requises : 192x192, 512x512. Format PNG.

3. **Service Worker** : Flutter génère un SW via `flutter build web --pwa-strategy=offline-first`. Vérifier que le SW est activé en production (actuellement désactivé en staging via `--pwa-strategy=none`). En prod, activer `offline-first` pour cacher l'app shell.

4. **Install prompt** : Implémenter un `InstallPromptBanner` dans `lib/core/widgets/`. Ce widget :
   - Écoute l'événement `beforeinstallprompt` (interop JS via `dart:js_interop`)
   - S'affiche après le 1er login réussi (voir D3)
   - Persiste le dismiss via `SharedPreferences` (clé `pwa_install_dismissed`)
   - N'affiche pas le banner si l'app est déjà en mode `standalone` (detecter via `window.matchMedia('(display-mode: standalone)')`)
   - Supporte aussi le flow iOS (bouton "Partager > Ajouter à l'écran d'accueil" avec instructions texte)

5. **Splash screen** : Auditer `web/index.html` — remplacer le spinner Flutter par défaut par la couleur primaire `#0F766E` en background.

---

### C. Setup déploiement prod (critique — bloque le go-live)

**Ce que cette sous-feature produit :**

1. **Environnement GitHub `production`** : Créer l'environnement dans les Settings GitHub. Ajouter les secrets suivants :
   - `SUPABASE_URL` (prod)
   - `SUPABASE_ANON_KEY` (prod)
   - `FIREBASE_SERVICE_ACCOUNT` (prod — JSON de compte de service Firebase)
   - `FIREBASE_PROJECT_ID` (prod)
   - `SUPABASE_PROJECT_REF` (prod — utilisé par `supabase db push`)
   - `SUPABASE_ACCESS_TOKEN` (prod)
   - `SUPABASE_DB_PASSWORD` (prod)
   - `RESEND_API_KEY` (prod)
   - `RESEND_FROM_EMAIL` (prod — domaine vérifié)

2. **Workflow CI/CD prod** : Modifier `.github/workflows/deploy.yml` pour ajouter un job `deploy-prod` déclenché sur push `main` :
   - `flutter build web --dart-define-from-file=dart-defines.prod.json --pwa-strategy=offline-first`
   - `firebase deploy --only hosting --project <prod-project-id>`
   - Le job utilise `environment: production`
   - Le job `apply-supabase-migrations` n'est PAS déclenché automatiquement — voir point 3

3. **Workflow migrations prod** (voir D5) : Créer un workflow séparé `.github/workflows/migrate-prod.yml` avec `on: workflow_dispatch`. Il exécute `supabase db push --linked` sur le projet prod. Nécessite confirmation manuelle depuis l'UI GitHub.

4. **`dart-defines.prod.json`** : Créer le fichier (non commité en clair — template dans `dart-defines.prod.json.example`) avec :
   ```json
   {
     "SUPABASE_URL": "<prod-url>",
     "SUPABASE_ANON_KEY": "<prod-anon-key>",
     "SUPABASE_SCHEMA": "public"
   }
   ```
   Le fichier réel est injecté depuis les secrets GitHub dans le job CI.

5. **Supabase Auth URL Configuration** : Dans Supabase Studio (projet prod), configurer :
   - Site URL : `https://<prod-domain>.web.app`
   - Redirect Allow-List : ajouter `https://<prod-domain>.web.app/**`

6. **Resend prod** : Vérifier le domaine email dans le dashboard Resend. Signer la DPA Resend. La variable `RESEND_FROM_EMAIL` en prod doit utiliser le domaine vérifié (ex: `noreply@easyrent.fr` plutôt qu'un domaine sandbox).

7. **Page `/privacy` complète** : Enrichir ou créer `lib/features/privacy/presentation/privacy_page.dart` avec les mentions obligatoires RGPD :
   - Identité du responsable de traitement
   - Base légale : art. 6.1.b RGPD (exécution d'un contrat)
   - Sous-traitants : Supabase (hébergement données), Resend (emails transactionnels), Firebase (hosting)
   - Conservation : 5 ans pour les documents bail_signé / état_des_lieux (obligation légale loi du 6 juillet 1989)
   - Droits des locataires (accès, rectification, effacement, portabilité)
   - Mention que les noms de fichiers uploadés peuvent contenir des données personnelles (PII)
   - URLs signées Storage valides 5 minutes uniquement (accès temporaire)
   - Contact DPO / responsable traitement

8. **Smoke test post-deploy** : Documenter une checklist dans `docs/DEPLOY_CHECKLIST.md` :
   - [ ] Login magic link fonctionne (email reçu, redirect OK)
   - [ ] Créer un bien immobilier
   - [ ] Créer un locataire
   - [ ] Créer un bail
   - [ ] Enregistrer un paiement
   - [ ] Générer une quittance PDF
   - [ ] Envoyer la quittance par email (vérifier réception)
   - [ ] Uploader un document
   - [ ] Dashboard affiche les KPI
   - [ ] PWA installable depuis Chrome (prompt visible)
   - [ ] `/privacy` accessible sans login

9. **Rollback strategy** : Documenter dans `docs/DEPLOY_CHECKLIST.md` la procédure de rollback :
   - Hosting : `firebase hosting:clone <prod-site>:<prod-site>@<previous-version>` ou redéploiement du commit précédent via le job CI
   - Migrations : Pas de rollback automatique — créer une migration de correction. Les rollbacks destructifs (DROP TABLE) sont interdits (rétention légale).

---

## Acceptance criteria (Gherkin)

**Sous-feature A — Dashboard**

- **Given** un bailleur avec au moins 1 bail actif, 1 paiement ce mois et 0 retard **When** il ouvre le dashboard **Then** il voit 4 KPI cards avec des valeurs numériques non vides et un montant "loyers ce mois" correct.

- **Given** un bailleur dont 1 locataire n'a pas payé ce mois **When** il ouvre le dashboard **Then** la KPI "Locataires en retard" affiche un compteur >= 1 avec une couleur d'alerte (error ou warningContainer du thème M3).

- **Given** un bailleur avec un bail dont `end_date` est dans 15 jours **When** il ouvre le dashboard **Then** la KPI "Baux à renouveler" affiche au moins 1.

- **Given** un bailleur avec 0 bien, 0 locataire, 0 bail **When** il ouvre le dashboard **Then** il voit l'écran "Premiers pas" avec 3 items de checklist cliquables, et aucune KPI card.

- **Given** un bailleur avec des paiements et quittances récents **When** il ouvre le dashboard **Then** la section "Activité récente" affiche les 5 dernières entrées triées par date décroissante, chaque entrée étant cliquable.

- **Given** l'app est ouverte sur un écran > 900px de large **When** le dashboard affiche les KPI **Then** les 4 cartes sont disposées en grille 4 colonnes.

**Sous-feature B — PWA**

- **Given** l'app est déployée en prod **When** un utilisateur Chrome visite l'URL pour la première fois après s'être connecté **Then** le banner "Installer EasyRent" s'affiche.

- **Given** l'utilisateur a cliqué "Fermer" sur le banner d'installation **When** il revient sur le dashboard **Then** le banner n'est plus affiché (dismiss persisté).

- **Given** l'app est installée en mode standalone **When** l'utilisateur ouvre l'app **Then** aucun banner d'installation n'est visible.

- **Given** l'app est déployée en prod avec `--pwa-strategy=offline-first` **When** l'utilisateur coupe sa connexion réseau **Then** l'app shell s'affiche (page blanche non visible) et un message "Mode hors-ligne" est montré.

- **Given** un audit Lighthouse est lancé sur la prod **Then** le score PWA est >= 90 (installabilité + service worker + manifest).

**Sous-feature C — Déploiement prod**

- **Given** un merge sur `main` **When** le workflow CI s'exécute **Then** un job `deploy-prod` se déclenche, build l'app avec `dart-defines.prod.json` et déploie sur Firebase Hosting prod.

- **Given** les migrations prod sont à appliquer **When** un développeur déclenche manuellement `migrate-prod.yml` depuis GitHub Actions **Then** `supabase db push` s'exécute sur le schéma `public` prod sans erreur.

- **Given** le 1er déploiement prod est terminé **When** la checklist smoke test `docs/DEPLOY_CHECKLIST.md` est exécutée **Then** tous les items passent (login → bien → locataire → bail → paiement → quittance → email → document → dashboard → PWA installable → `/privacy`).

- **Given** un utilisateur non authentifié visite `/privacy` **Then** la page est accessible (pas de redirect vers login) et liste les sous-traitants (Supabase, Resend, Firebase) et la durée de conservation de 5 ans.

---

## Out of scope

- Charts / graphiques (barchart "encaissé / dû" mensuel) — P1, amorce architecturale seulement dans `KpiCard`
- Icônes PWA custom avec design graphique professionnel — P1 (placeholder "ER" utilisé en MVP)
- Notifications push PWA — P1
- Export des données RGPD (droit à la portabilité) — P1
- Effacement des données RGPD self-service — P1
- Monitoring prod (alertes Sentry, logs structurés) — P1
- Multi-environnements autres que staging / prod
- Hardening flag GUC `app.allow_deleted_at_change` (dette FEAT-002, P1)

---

## Dependencies

**Tables Supabase :**
- `public.leases` (KPI baux actifs, renouvellement)
- `public.payments` (KPI loyers du mois, retards)
- `public.receipts` (activité récente)
- `public.documents` (KPI documents en attente — FEAT-009)
- `public.properties`, `public.tenants` (écran onboarding)

**Features bloquantes :**
- FEAT-001 (auth) — prod auth URL config
- FEAT-006 (payments) — KPI loyers
- FEAT-007 (receipts) — activité récente
- FEAT-008 (email) — smoke test email
- FEAT-009 (documents) — KPI documents (optionnel)

**Infrastructure :**
- GitHub Environments (production) avec tous les secrets listés en C.1
- Firebase projet prod existant (project ID connu)
- Supabase projet prod avec schéma `public` prêt
- Resend domaine vérifié

---

## Legal / compliance notes

- **Conservation 5 ans** : Les documents `bail_signe` et `etat_des_lieux` sont soumis à conservation légale (loi du 6 juillet 1989). Aucune suppression automatique. La page `/privacy` doit en faire mention explicitement.
- **RGPD art. 6.1.b** : Base légale = exécution du contrat de bail entre bailleur et locataire. À mentionner dans `/privacy`.
- **Sous-traitants RGPD** : Supabase (données hébergées EU), Resend (emails transactionnels), Firebase (hosting statique). Chaque sous-traitant doit être listé dans `/privacy` avec sa finalité.
- **Noms de fichiers PII** : Les filenames uploadés (FEAT-009) peuvent contenir des noms de locataires. La politique de confidentialité doit signaler que les métadonnées de fichiers sont traitées comme des données personnelles.
- **Bucket Storage privé** : Les URLs signées (5 minutes) garantissent que les documents ne sont pas accessibles publiquement. À mentionner dans `/privacy`.
- **Droit à l'effacement** : En MVP, l'effacement est implémenté via soft-delete. Un contact DPO doit être fourni pour les demandes manuelles jusqu'à l'implémentation du self-service RGPD (P1).

---

## Risques et contraintes

| Risque | Impact | Mitigation |
|---|---|---|
| FEAT-010 est la plus grosse story du MVP (3 concerns) — risque de blocage sur C pendant que A/B avancent | Haut | Implémenter C en premier ou en parallèle. A et B peuvent avancer indépendamment. |
| 1er déploiement prod peut révéler des bugs cachés (Supabase Auth URL non configurée, secrets manquants, Edge Functions non déployées sur prod) | Haut | Prévoir 0,5j de buffer pour le debugging post-deploy. Prioriser le smoke test complet dès le 1er deploy. |
| Vision "financial dashboard" = scope creep évident | Moyen | Strict text-only pour les KPI. L'extension charts est explicitement P1. La `KpiCard` doit avoir un slot `child` optionnel mais vide en MVP. |
| Service Worker `offline-first` peut poser des problèmes de cache stale en prod | Moyen | Vérifier que le header `Cache-Control` est correct sur Firebase Hosting. Tester le update flow (SW update prompt). |
| Migrations prod sans rollback automatique | Moyen | Workflow `workflow_dispatch` avec confirmation. Ne jamais appliquer de migration destructive sans backup préalable. |
| Page `/privacy` incomplète peut exposer à une non-conformité RGPD dès le go-live | Haut | La page `/privacy` est un AC bloquant pour le go-live. Elle doit être accessible sans login. |

---

## Recommandation de découpage

Cette story peut être découpée en 3 tickets d'implémentation distincts si nécessaire :

- **FEAT-010A** — Dashboard refonte (A) — M (2 jours)
- **FEAT-010B** — Polish PWA (B) — S (0,5 jour)
- **FEAT-010C** — Setup déploiement prod (C) — M (1,5 jour + 0,5j buffer go-live)

Le découpage est recommandé si les sous-features sont assignées à des personnes différentes ou si FEAT-010C doit être finalisée avant FEAT-010A/B pour des raisons de planning.

---

## Priority

P0 (MVP) — C'est la dernière feature avant le 1er déploiement prod.

## Estimated effort

**L (> 3 jours)** au total, décomposé :
- FEAT-010A (dashboard) : M — 2 jours
- FEAT-010B (PWA polish) : S — 0,5 jour
- FEAT-010C (prod setup + smoke test) : M — 1,5 jour + 0,5j buffer

**Total : ~4,5 jours** — Justifie un découpage en 3 tickets séparés.

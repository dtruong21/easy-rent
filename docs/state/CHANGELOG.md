# Historique des changements (état projet)

> **Fichier d'archive — NE PAS auto-charger.** Sorti de `INDEX.md` (diète tokens
> 2026-07-09) pour que le routeur d'état reste léger. À consulter uniquement pour
> l'historique détaillé d'une feature. Le statut courant vit dans
> [`FEATURES.md`](FEATURES.md) (matrice) ; les détails techniques dans les shards
> `schema/`, `functions/`, `routes/`.

## 🗂️ Archives par période

Ce fichier ne porte que la **période courante**. L'historique ancien est archivé
par mois dans [`changelog/`](changelog/) — c'est ce qui l'empêche de grossir sans
fin (il avait atteint ~11k tokens avant l'archivage du 2026-07-30).

| Période | Fichier | Entrées |
|---|---|---|
| Juillet 2026 (périodes closes) | [`changelog/2026-07.md`](changelog/2026-07.md) | 49 |

#### Règle de roulement (à appliquer par `state-keeper`)

> `###` est réservé aux entrées de changelog — d'où le `####` ici, pour que
> `grep -c '^### '` compte juste les entrées et rien d'autre.

1. Les nouvelles entrées se **préfixent** dans la section « période courante »
   ci-dessous.
2. Quand la période courante dépasse ~10 entrées **ou** qu'un mois se termine :
   déplacer ses entrées dans `changelog/<AAAA-MM>.md` (créer le fichier au
   besoin, avec l'en-tête « archive figée »), ajouter une ligne au tableau
   ci-dessus, et repartir d'une section courante vide.
3. **Ne jamais réécrire une archive** : elle est figée. On n'y corrige qu'une
   erreur factuelle avérée.

## Changements (2026-08-03 → 2026-10-04)

### FIX cartes : nettoyage après FEAT-059 (#198) (2026-10-04)
- Code mort supprimé : `CardActionButton`, `CardActionIconButton`, `EntityCardHeader`. `kCardActionButtonHeight` vit désormais dans `summary_card.dart` et règle aussi la hauteur de `SummaryQuickActionButton`. `EntityCard` reste pour les cartes de scénarios du simulateur.
- `CardGrid` : en grille (desktop), la hauteur de cellule `mainAxisExtent` grandit avec la taille de texte d'accessibilité. Une carte complète débordait de 22 px à l'échelle 2.0 ; un test « pire cas » couvre les échelles 1.0, 1.3 et 2.0.
- `CardSkeleton` reprend la forme d'une `SummaryCard` : liseré, chiffre clé à droite, statut et info.
- Tests ajoutés pour Appeler / Email de la carte locataire (`tel:` sans espaces, SnackBar en cas d'échec). Ajout en dev-dependencies de `url_launcher_platform_interface` et `plugin_platform_interface`, pour le faux lanceur d'URL.

### Connexion v1 : Google + email, email seul sur iOS (2026-10-03)
- Décision produit : la v1 ne propose que Google et email / mot de passe ; Apple viendra après la première version. `lib/core/config/auth_providers.dart` : Google proposé sur web et Android, **masqué sur iOS** (règle App Store 4.8 : pas de connexion tierce sans option équivalente type Apple) ; Apple masqué partout. Formulaires de connexion et d'inscription (dont le passage d'un essai anonyme à un compte complet) filtrés ; la ré-authentification des comptes existants est inchangée. Code Apple conservé et testé (forçage de test) pour la réactivation.

### FIX cartes : un montant géant ne fait plus déborder `SummaryCard` (2026-10-03)
- Vu à la première CI depuis le retour du quota Actions : `receipts_card_view_test` « pire cas desktop 1280 px » débordait de 3,1 px sur Linux (police de secours plus large pour « € » et l'espace fine). Le chiffre clé est plafonné à 45 % de la rangée et réduit à l'échelle au-delà (jamais tronqué) ; nouveau test reproductible (carte de 240 px, 1 234 567,89 €).

### FIX sécurité OWASP (2026-09-30)
- Audit [`docs/security/owasp-audit-2026-09-30.md`](../security/owasp-audit-2026-09-30.md) (21 constats) : 6 constats traités sur `fix/owasp-security` : 01, 02, 05 corrigés ; 04, 06, 09 partiellement (voir le statut de l'audit) ; OWASP-21 (tests Storage) couvert au passage par OWASP-04 ; statut par constat en tête du rapport.
- OWASP-01 (c88f361) : un achat en mode test ne peut plus accorder un palier en prod — le webhook RevenueCat route par `event.environment` (`SANDBOX` → `staging`, `PRODUCTION` → `(default)`, autre → ignoré, aucun repli) ; `createCheckoutSession` refuse `landlord_not_found` ; le cron de réconciliation ignore les achats sandbox. Conséquence : un achat sandbox (App Review / TestFlight) sur un compte prod ne débloque rien tant qu'une allowlist serveur n'existe pas (feature achat intégré).
- OWASP-05 (9922767) : `deleteAccount` hard-delete aussi `charge_statements` et `etat_des_lieux` ; test de parité export ⊆ purgé ∪ retenu (`receipts`).
- OWASP-02 (7c8ef23) : email vérifié exigé côté serveur — `hasTrustedEmail()` dans `firestore.rules` (`isFullyAuthed()`, `isOwner()`), `requireVerifiedUid` sur 22 callables (exemptées : `deleteAccount`, `exportAccountData`, `finalizeAnonymousUpgrade`).
- OWASP-04 (3221965) : écritures Storage réservées aux comptes non anonymes à email de confiance, nom d'objet contraint ; `cleanupExpiredAnon` purge `documents/{uid}/` ; 34 tests de règles Storage dans `npm run test:rules` (Firestore + Storage, cache CI v2).
- Revue finale : `cleanupExpiredAnon` relit l'utilisateur Auth et **ignore** tout compte à `providerData` non vide (upgradé, ex. `finalizeAnonymousUpgrade` interrompu après le link) au lieu de le purger ; `timeoutSeconds: 300`.
- OWASP-06 (c0e5f19) : en-têtes de sécurité HTTP sur les 4 cibles Hosting ; app : `frame-ancestors 'none'` appliqué + CSP complète en Report-Only (7 hashes liés aux scripts inline de `web/index.html` et à FlutterFire) ; vitrine : CSP appliquée.
- OWASP-09 (b6d5e7c) : `npm audit fix` sur `functions/` (lockfile seul) — advisories de prod 16 (5 high) → 9 (2 high) ; le reste exige firebase-admin 14 / firebase-functions 7.
- **Redéploiement des Functions requis** (webhook, checkout, cron, `deleteAccount`, garde des callables, `cleanupExpiredAnon`). Règles Firestore : CI (`firestore:staging` sur `develop`, `(default)` sur `main`) ; `storage.rules` : `deploy.yml` depuis `main` seulement ; en-têtes : CI avec le Hosting. Action manuelle recommandée : vérifier les réglages d'environnement du webhook dans RevenueCat (cf. `docs/SECURITY.md`).
- Doc : ADR 0003 amendée (webhook par `event.environment`), `ENVIRONMENTS.md` (« Facturation »), `SECURITY.md` (audit + couplage CSP), `DEPENDENCIES.md` (en-têtes réels), `LEGAL.md`, shards `functions/account`, `functions/README`, `schema/leases`.

### FIX conformité stores (2026-09-30)
- Audit stores : apps iOS/Android sans aucun achat hors store (`isStoreApp` : `/pro` = message neutre, entrées vers `/pro`, « Réactiver » Stripe et section « Prochainement Plan Pro » masqués) ; page de suppression de compte prévient pour les abonnements store (non résiliés) et web (résiliés, sans remboursement) ; `NSPhotoLibraryUsageDescription` ajouté (ITMS-90683). Décision : achat intégré RevenueCat avant la sortie des apps (Apple 3.1.3(b)).
- Functions : `deleteAccount` résilie immédiatement les abonnements Stripe gérables **avant** la purge, pour les seuls comptes facturés web (clé par base du compte ; échec → `internal`, rien purgé ; sautée sous émulateur). **Redéploiement des Functions requis** — vérifier d'abord dans Secret Manager que `STRIPE_SECRET_KEY` est live et `STRIPE_SECRET_KEY_TEST` test, sinon les comptes facturés web ne peuvent pas être supprimés.
- Functions (décision 2026-09-30) : `deleteAccount` choisit la clé Stripe par la **seule base routée** (`staging` → test, sinon live), Origin ignoré — l'URL Firebase Hosting de prod déclarée aux stores n'est plus refusée (`origin_not_allowed` → boucle « session trop ancienne ») et localhost n'obtient plus la clé test contre la prod.
- Functions : `manageSubscription` accepte `cancel` **sans Origin** (apps natives, clé par base du compte) pour que « Résilier » marche dans les apps ; `reactivate`/`change_plan` sans Origin restent refusés (`origin_not_allowed`) avant tout appel Stripe. **Redéploiement des Functions requis.**
- Ré-audit consigné dans `docs/STORE_COMPLIANCE.md` (target SDK 36, 16 Ko, permissions, iOS 15 / Xcode 27 vérifiés). Bloquant restant : mentions légales encore en brouillon dans l'app (Apple 2.1).

### FIX baux : la puce « Actifs » compte tous les baux en cours (2026-09-29)
- Vu au premier Robo Test Lab : « Actifs 0 » alors que 3 baux en cours étaient tous en retard. `leaseMatchesFilter` : « Actifs » = `status == active` (en retard et à renouveler inclus), comme « Loués » (biens) et « Avec bail » (locataires) ; « À renouveler » / « En retard » restent des sous-ensembles (priorité late > renewable entre eux, comme la pastille de carte).

### Cloud Functions : runtime Node.js 22 (2026-09-29)
- `firebase.json` `nodejs20` → `nodejs22`, `engines.node` 22, `@types/node` ^22, jobs CI functions + règles en Node 22. Node 20 est décommissionné le 2026-10-30 (plus de déploiement possible après). `firebase-functions` reste en v6 (montée de version majeure à part).
- Vérifié sous Node 22 : lint, build, 521 tests, 96 tests de règles, émulateur Functions (38 fonctions chargées). **Redéploiement de toutes les Functions requis** pour basculer le runtime.

### Build Android de test sur staging — Test Lab (2026-09-29)
- Functions : `dbForRequest` async — web routé par Origin (inchangé), appels mobiles (sans Origin) routés par la base du compte (`dbForLandlordUid`, prod d'abord). **Redéploiement de toutes les Functions requis.**
- App : réglage `MOBILE_STAGING` (ignoré en release) → base `staging`, auto-login d'un compte de test staging-only (`dart-defines.testlab.json`, gitignoré), ruban « STAGING ».
- Doc : `docs/MOBILE.md` (Test Lab / Robo), ADR 0003 amendée, domaine staging corrigé dans `ENVIRONMENTS.md`.
- Outil : `tool/seed/seed_testlab_staging.mjs` — sème le compte de test (Auth email vérifié, `landlords/{uid}` dans `staging` seulement, données via les callables avec l'Origin staging web) et écrit `dart-defines.testlab.json` ; refuse tout compte présent en prod.

### FEAT-059 — Cartes de liste « chiffre clé » + puces de filtre (2026-09-29)
- `SummaryCard` (core) : liseré couleur du bien, montant en gros à droite, 1 action rapide + menu ⋮ ; ~90 px au lieu de ~150. Adaptateurs : `PropertyCard`, `LeaseCard`, `TenantCard` (Appeler / email), `ReceiptCard` (Envoyer = `ShareReceiptButton`).
- `FilterChipsBar` (core) : puces avec compteurs dérivés client (`…FilterCountsProvider`, prédicats `…MatchesFilter` extraits sans changement de règle) ; remplace dropdown mobile et `SegmentedButton` desktop.
- Quittances mobile : timeline sans colonne de marqueurs, en-têtes d'année conservés.
- Données : `PropertyListItem.currentRentCcCents`, `TenantListItem.activeLeaseChargesCents`. Android : intent `DIAL` dans `<queries>`.
- Client uniquement — aucun déploiement backend.
- Page Quittances : sélecteur de vue « Chronologie / Cartes » (libellés dédiés, `ViewModeToggle` accepte `cardsLabel`/`tableLabel`).

### PR #193/#194/#195 — FIX recette mobile iOS (2026-09-28)
- **#193** Build iOS Xcode 27 : cible minimale 15.0 (Runner + pods), retrait du pod `FirebaseFirestore` précompilé (doublon avec Swift Package Manager, Flutter 3.44). Debug émulateur : Functions + Storage branchés (ports surchargeables par dart-define). Functions : `FieldValue`/`Timestamp` via `firebase-admin/firestore` (16 fichiers — le proxy de l'émulateur perdait `admin.firestore.FieldValue`) → **redéployer toutes les functions**.
- **#194** PDF quittance/EDL sur mobile = feuille de partage système (le repli `data:` n'ouvrait rien sur iOS). Liste EDL invalidée après création (`etatDesLieuxListProvider` déplacé en `application/`) + formulaire refermé (anti-doublon). Onboarding étape 5 et CTA Quittances vides → fiche du bail. Bandeau Quittances : plus de débordement.
- **#195** `CardGrid` : en colonne unique, cartes en hauteur naturelle (la hauteur fixe desktop laissait ~70 px de vide sur mobile).
- Recette : iOS simulateur contre émulateurs (recette dans la mémoire `mobile-emulator-testing`).

### FEAT-037 — État des lieux digital (V1) (2026-09-16)
- Saisie entrée/sortie du locataire ou propriétaire : pièces + éléments + état + compteurs + clés, formulaire complet `EtatDesLieuxFormPage`.
- Rendu PDF côté client (pattern `pdf` + `share_plus`, comme quittances) conforme décret 2016-382 : mentions légales propriétaire + **domicile du bailleur** obligatoirement figés au moment de la saisie.
- Nouvelle collection immuable CF-exclusive `etat_des_lieux/{id}` (patron `charge_statements`) : parties + adresse bien + identité bailleur figées ; aucun soft-delete, rétention légale 5 ans. Index composite `(landlordId, leaseId, createdAt DESC)` pour historique par bail.
- Repository `EtatDesLieuxRepository` (create via callable, listForLease, getById) + provider Riverpod.
- UI : liste `EtatDesLieuxListPage` affiche historique entées/sorties du bail + bouton « Nouveau », routes `/leases/:id/etat-des-lieux` + `/new`. Entrée fiche bail via bouton section dédiée.
- **Déploiement reporté** (gel GitHub Actions, Plan A) : Cloud Functions callable `createEtatDesLieux` + Firestore rules/indexes à déployer **manuellement au reset quota** (après merge `feat/037-etat-des-lieux` → `develop` → `main`). Rules du streaming ont un déploiement auto (CI), pas les Functions.
- **Cuts V2** : photos, signature électronique, comparaison automatique entrée↔sortie (non construit dans ce plan).

### FEAT-058 — Onboarding progressif jusqu'à la 1re quittance (2026-09-15)
- Checklist d'onboarding progressive du dashboard : 5 étapes (bien → locataire → bail → paiement → quittance), chacune dérivée des données (non-vide = cochée) via `DashboardRepository.fetchOnboardingProgress()` → modèle `OnboardingProgress`. Affichée tant qu'aucune quittance (`hasReceipt == false`) ET non explicitement passée (`onboardingDismissedProvider`, SharedPreferences). Étapes 4–5 lease-scoped (désactivées sans bail). Dismiss local (bouton « Passer ») persiste en SharedPreferences (`onboarding_dismissed:bool`).
- **100 % client** : lecture seule des données Firestore, zéro backend, zéro Cloud Function, zéro déploiement serveur. Intégré au snapshot dashboard existant (`DashboardSnapshot.onboarding`), aucune requête additionnelle.

### FEAT-046 — Purge différée des quittances (cron RGPD) (2026-09-15)
- Cron quotidien (03:00 Europe/Paris, région europe-west1) purge les quittances expirées selon RGPD art. 5.1.e : hard-delete `receipts where retentionUntil <= now` sur la base `(default)`. Champ `retentionUntil` posé par `stampRetainedReceipts` lors de la suppression de compte (FEAT-045), valeur = date de suppression + 5 ans (rétention légale loi 6/7/1989).
- **Implémentation** : fonction pure idempotente `purgeExpiredReceiptsImpl(db, now)` pagine 400 docs/itération, max 2000 hard-deletes/run, aucun accès Storage. Fonction main `purgeExpiredReceipts` wrappée via `onSchedule`. Fichier `functions/src/scheduled/purge_expired_receipts.ts`.
- **Déploiement** : Cloud Functions restent hors CI (ADR 0003) — **déploiement manuel après merge**. Règles Firestore et indexes déployés automatiquement par CI.
- Tests : `functions/src/__tests__/purge_expired_receipts.test.ts` (5 cas : aucune quittance à purger, une à purger, pagination, limites MAX_DELETES_PER_RUN, idempotence).

### PR #188 — FIX documents : action « Modifier la catégorie » cassée (2026-09-15)
- L'action était câblée UI (`EditCategoryDialog` → contrôleur → repository) mais `FirestoreDocumentsRepository.updateCategory` jetait `UnsupportedError` à chaque appel — Callable serveur jamais écrite. Reclasser un document = erreur systématique. Trouvé au discovery 2026-09-15.
- **Serveur** : nouvelle Callable `updateDocumentCategory` (`functions/src/callable/documents.ts`, exportée `index.ts`). Reclasse `category` (seul champ mutable), recalcule `legalHold`, revalide ownership + non-supprimé + `ALLOWED_CATEGORIES`. **Garde-fou** : refuse (`FAILED_PRECONDITION` `document_under_legal_hold`) un document **déjà** sous `legalHold`, comme `softDeleteEntity`.
- **Client** : `updateCategory` invoque la Callable puis relit via `getById` ; refus legalHold mappé vers `UpdateCategoryErrorReason.legalHold` + message FR/EN dédié.
- Tests : `update_document_category.test.ts` (8 cas) + cas legalHold dans le test contrôleur Dart. **Cloud Functions modifiées → déploiement manuel** après merge.

### FEAT-032 — Trésorerie graphique « encaissé vs dû » : superseded (2026-09-15, décision PM)
- Le livrable littéral de FEAT-032 (barchart mensuel « encaissé vs dû ») a été **délibérément supprimé en FEAT-027** au profit du graphe **cash-flow net réel** (loyers encaissés − dépenses non-récupérables − mensualité prêt). Rationale FEAT-027, dans le code : « un loyer est fixe, le voir en barres n'apprend rien au bailleur » (`monthly_cashflow.dart:5-9`, `monthly_cashflow_chart.dart:23-27`).
- FEAT-032 marqué `❌ superseded` : le graphe visé existe déjà sous une meilleure forme. Aucun code. La série temporelle des impayés (« attendu vs encaissé » par mois) reste un angle distinct possible en V2, mais recoupe partiellement FEAT-028 (retard courant) + indicateur ponctualité (#178) — à re-cadrer si repris.

### FEAT-031 V1 — Relance de paiement assistée (client-side) (2026-09-14, branche `feat/payment-reminder-assisted`)
- Bouton « Relancer le locataire » sur la fiche bail (FEAT-005), visible si bail en retard (`isLate`, FEAT-028). Lance le choix de canal, pré-remplit message amiable détaillé.
- **Canaux** : email (`mailto:`), SMS (`sms:`), WhatsApp (`https://wa.me/…` FR-numbers seulement). Ouvre le client du propriétaire (100 % client via `launchUrl`, zéro backend).
- **Message pré-rempli** : période due + montant (loyers + charges) + identité propriétaire/bien, mention explicite « relance amiable, pas une mise en demeure ».
- **Pas de backend, pas de secret, pas de Cloud Function** — 100 % client (calcul + launchUrl).
- **Fichiers nouveaux** : `lib/features/leases/domain/payment_reminder_message.dart`, `lib/features/leases/domain/payment_reminder_channel.dart`, `lib/features/leases/presentation/widgets/payment_reminder_button.dart`, `lib/core/utils/phone_uri.dart` ; public `leaseCurrentDueMonth` dans `lib/features/leases/domain/lease_lateness.dart`.
- **V2 (non construit)** : automatisation cron serveur (nécessite enabler email — Resend/Trigger Email — pas encore en place).

### FEAT-033 — Archivage régularisations charges : snapshot figé immuable (2026-09-14, branche `feat/charge-statement-snapshot`)
- Nouvelle collection `charge_statements/{id}` — **CF exclusive, IMMUABLE** (Rules `get,list: if isOwner(landlordId)` ; `create,update,delete: if false`). Pas de soft-delete (rétention légale 5 ans, décret 87-713) ; les décomptes annulés (`isVoided`) restent lisibles pour audit. Champs : identité figée à la finalisation (`landlordFullName/Address`, `tenantFullName/FirstName`, `propertyName/Address`), période (`periodStart/periodEnd`), `provisionsCollectedCents` (recalculé serveur), `actualExpensesCents` + `actualExpensesSource` ('expenses'|'manual'), `balanceCents` (signé), `lineItems[]` figé (`expenseId, nature, notes, amountCents, expenseDate`), `createdAt`, `isVoided/voidedAt/voidedReason`, `sentAt/sentToEmail`, `schemaVersion:1`.
- 3 callables `europe-west1` (`functions/src/callable/charge_statements.ts`), patron répliqué de `receipts` (FEAT-007) : `finalizeChargeRegularization` (auth + ownership bail + **gate légal serveur** `resolveChargeMode(...)==='provisions'` sinon `charge_regularization_not_applicable` ; **provisions recalculées serveur** — jamais acceptées du client, via `sumProvisionsOverlap` sur les paiements de la période ; si `actualExpensesSource==='expenses'` la somme des `lineItems` doit égaler `actualExpensesCents` sinon `invalid-argument` ; écrit le snapshot immuable), `voidChargeStatement` (idempotent, non destructif — flag seulement), `markChargeStatementAsSent` (audit d'envoi, rejette un décompte déjà `isVoided`).
- Index composite `charge_statements(landlordId ASC, leaseId ASC, createdAt DESC)` — nécessaire à `listForLease` côté historique fiche bail.
- Ajouté à l'export RGPD `exportAccountData` (clé `chargeStatements`, `functions/src/callable/export_account_data.ts:25`).
- Flutter : modèle `ChargeStatement`, repository + provider, controller de finalisation, action « Finaliser & figer » dans le dialogue de régularisation de charges, section historique sur la fiche bail. PDF re-rendu côté client à partir des champs figés (pas de PDF/Storage serveur, même patron que les quittances).
- **Déploiement** : Rules + index déployés automatiquement par la CI (`develop` → base `staging`). Cloud Functions (les 3 callables) restent **hors CI — déploiement manuel délibéré** (ADR 0003) ; sans ce déploiement, l'action « Finaliser » échoue en staging (callable introuvable) même client déployé.
- État FEATURES.md : `FEAT-033` passé `💡 idea` → `✅ done` (domaine `leases`).
- **Nettoyage revue finale** (PR #182 + suivi) : `finalizeAndShare` source le message de partage depuis le snapshot figé (plus depuis le formulaire) ; suppression de l'ancien contrôleur volatile `charge_regularization_share_controller.dart` (mort) ; retrait des params d'identité morts de `ChargeRegularizationDialog` et `ChargeRegularizationSection` (+ locals/imports orphelins de `lease_detail_page`) ; `getById` lève `ChargeStatementNotFoundException` dédiée ; ajout d'un test widget du flux d'annulation (dialog motif → `voidStatement`). Déployé staging le 2026-09-14.

### PR #181 — FIX ponctualité : faux retards (bug fuseau horaire) (2026-09-13, commit db4f12c)
- L'indicateur de ponctualité (#175 fiche bail + #178 fiche locataire) affichait de faux retards. `computePaymentPunctuality` lisait `periodStart.month`/`paidAt` sur des `DateTime` **UTC** (écrits `.toUtc().toIso8601String()`, relus `DateTime.parse("…Z")`) : à l'est d'UTC, « 01/08 » local stocké `2026-07-31T22:00Z` → mois lu = juillet → échéance un mois trop tôt → tout en retard (systématique bailleurs FR, périodes le 1er).
- Fix : normalise `periodStart`/`paidAt` via `leaseLocalDate` (toLocal + troncature) avant calcul, comme `isLeaseLate` (KPI Retards, déjà correct) et `FrenchDate.format`. `_dateOnly` de `lease_lateness` exposé en `leaseLocalDate` (public, partagé) — aucune duplication, aucun changement de stockage. Dashboard non affecté.
- Test d'invariance round-trip UTC (même pattern que `lease_lateness_test`). Suite complète verte (2908), analyze + dart format clean.

### PR #180 — FEAT-047 : export des données RGPD (accès + portabilité) (2026-09-12, commit 3abf91e)
- Droit d'accès (art. 15) + portabilité (art. 20) : callable `exportAccountData` (europe-west1) parcourt en lecture toutes les collections du bailleur (`properties, tenants, leases, payments, receipts, documents, expenses, investment_scenarios, support_requests` + singletons `landlords/{uid}`, `paid_plan_interest/{uid}`) via `dbForRequest` + `landlordId == uid`, sérialise les Timestamp en ISO, renvoie un **JSON structuré unique** (inline). Soft-deleted inclus (transparence), binaires référencés (chemins) non empaquetés. Honore `docs/LEGAL.md:28`.
- Garde d'auth récente (< 5 min, non-anonymes) **extraite en helper partagé** `assertRecentAuthForNonAnonymousAccount` (réutilisée par `deleteAccount`). **Isolation cross-user** : filtre `landlordId` sur chaque requête (Admin SDK bypasse les rules) — vérifié en revue finale sur les 11 accès.
- Client : `AccountExportRepository` + `ExportDataController` (idle/loading/success/error) + tuile « Exporter mes données » dans Profil ; `WebShareService.deliverFile` générique (web download / mobile share, révocation blob différée pour Safari). i18n FR/EN.
- TDD (5 tâches subagent-driven, revue finale whole-branch APPROVE). **Functions 466/466**, **Flutter 2907/2907**, analyze + dart format clean.

### PR #179 — FIX Accueil : cartes patrimoine compactes + couleur par palier du rendement (2026-09-11, commit 97717a7)
- Retour propriétaire sur la zone « Mon patrimoine » (#177). `KpiGrid` : les 2 tuiles (occupation, patrimoine) étaient étirées à ~460 px (childAspectRatio dépendant de la largeur, absurde avec 2 colonnes en large). Remplacé par une hauteur de tuile fixe (`mainAxisExtent: 180`) → cartes compactes, robustes à toute largeur.
- `PortfolioYield` : la valeur de rendement (brut/net) est colorée par palier (`yieldTierFor`) — < 0 % rouge, 0–10 % jaune, ≥ 10 % vert ; « — » (non calculable) garde la couleur par défaut. La couleur renforce, le « X.XX % » reste lisible sans teinte (accessibilité). Jetons de design uniquement, aucune couleur en dur ; aucune requête ni clé i18n nouvelle. Suite complète verte (2898).

### PR #178 — Fiche locataire : ponctualité de paiement agrégée (par locataire) (2026-09-11, commit ec1de24)
- Suite de #175 (ponctualité par bail). Sur la fiche locataire : indicateur factuel **agrégé** sur tous les baux du locataire (en tête) + ponctualité **par bail** (#175) sur chaque ligne de la section « Baux ». « Par locataire » = le propre historique factuel d'un locataire (multi-baux) — **jamais** un comparatif/classement/liste noire inter-locataires (garde-fou #175 vérifié en revue finale : agrégat mono-locataire, keyé par `tenantId`).
- `combinePaymentPunctuality(parts)` (helper pur additif) ; `PaymentPunctualityView` extrait de l'indicateur #175 (rendu réutilisable, partagé par-bail + agrégat) ; `payment_day` exposé dans la projection `listLeasesForTenant` ; `tenantLeasesProvider` + `TenantPunctualityIndicator` (un bail en chargement → rien ; 0 paiement → rien ; % si total ≥ 3).
- Accès Firestore jamais en direct (`leasePaymentsProvider` + `tenantRepositoryProvider`), aucune persistance de score, jamais partagé/exporté. Jetons de design, i18n réutilisée (aucune nouvelle clé). TDD (5 tâches subagent-driven), revue finale whole-branch APPROVE. `flutter analyze` clean, suite complète verte (2894).

### PR #177 — Accueil : cockpit à 3 zones (À traiter / Mon patrimoine / Analyse) (2026-09-11, commit b343ebe)
- La structure de l'Accueil était à plat (un seul en-tête « Vue d'ensemble » sur 5 blocs hétérogènes) : actions/états/analyse mélangés, redondance patrimoniale, « docs » mal rangé. Restructuration en **3 zones nommées** (`SectionHeader`), réordonnées **actions d'abord** : Zone 1 « À traiter » (ActionItemsPanel : encaissement · retards · baux finissant) → Zone 2 « Mon patrimoine » (occupation · patrimoine · rendement brut/net) → Zone 3 « Analyse » (graphe cash-flow · activité récente).
- **Docs** déplacé de la grille KPI vers une **ligne passive** « N documents en attente » en bas de « À traiter » (pas de tap : aucune page documents globale n'existe), masquée si 0. `KpiGrid` réduit à 2 tuiles (occupation, patrimoine) et perd son paramètre `snapshot`. Titre interne redondant de l'ActionItemsPanel retiré (la zone le nomme).
- **Dédup cash-flow** : la carte « total mensuel » de PortfolioYield disparaît ; le graphe historique reste la seule représentation. En corollaire, l'agrégat mort `totalMonthlyCashflowCents` **et la requête `expensesRepository.listAllForLandlord()` qui l'alimentait** (inerte — les rendements brut/net n'utilisent que les charges déclarées) sont supprimés → **une requête Firestore en moins par chargement**. Caption « à ne pas confondre avec… » obsolète nettoyée.
- **Zéro nouvelle requête Firestore** (une supprimée). Pure recomposition ; jetons de design, i18n FR/EN, responsive. TDD (4 tâches, subagent-driven), revue finale whole-branch. `flutter analyze` clean, suite complète verte (2886).

### PR #176 — FIX Dashboard : suppression du KPI renouvellements orphelin (requête Firestore morte) (2026-09-09, commit a9f2c7e)
- La PR #174 a retiré le KPI « Baux à renouveler » de l'UI mais `fetchRenouvellements()` restait dans le fan-in de `DashboardController.build()` : une requête Firestore sur `leases` (fenêtre 60 j) partait à **chaque** chargement du dashboard, résultat jamais lu (`DashboardSnapshot.renouvellements` sans consommateur UI). Requête gaspillée + champ mort — nettoyage signalé par #174.
- Retire `RenouvellementsKpi`, `fetchRenouvellements` (interface + impl Firestore), le champ `DashboardSnapshot.renouvellements` (+ `empty()`), le fan-in/construction du snapshot dans `dashboard_provider.dart`, et l'import `lease_renewal` devenu inutile dans le repository.
- **Inchangé** : `kLeaseRenewalWindowDays` / `isLeaseRenewable` restent consommés par le filtre de la liste des baux et le panneau « baux finissant » (#171). Seul le consommateur KPI mort est retiré.
- 3 groupes de tests portant sur `fetchRenouvellements`/`RenouvellementsKpi` retirés (dont la « fenêtre 60 j » de #172), fakes de repository nettoyés (7 fichiers). Suite complète verte (2885, −9 tests), `flutter analyze` clean.

### PR #175 — Fiche bail : indicateur de ponctualité de paiement (factuel, responsive) (2026-09-09, commit 56d7531)
- Alternative légale à la « notation de locataire » (écartée : risque RGPD/profilage/discrimination). Indicateur **purement factuel** en tête de la section « Paiements » de la fiche bail : parmi les paiements enregistrés, X/Y à l'heure · N en retard · % (le % seulement si ≥ 3 paiements). Privé au bailleur, jamais partagé, aucun score/lettre/étoiles, aucune agrégation inter-locataires.
- `leaseDueDate({paymentDay, year, month})` extrait de `lease_lateness.dart` (échéance = `min(paymentDay, dernier jour du mois)`), réutilisé sans dupliquer le clamp. Helper pur `computePaymentPunctuality(payments, {paymentDay, graceDays})` → `PaymentPunctuality {total, onTime}` (+ `late`, `hasPayments`, `onTimePercent`). À l'heure = `paidAt ≤ échéance + 5 j` (`kDefaultLeaseGraceDays`, même définition que `lease_lateness`) ; soft-deleted ignorés.
- Widget `PaymentPunctualityIndicator` responsive : ≥ 600 px ligne complète, < 600 px pill compact dans la même rangée (aucun scroll ajouté), tap → feuille de détail (méthode + note de confidentialité). Ligne et pill ellipsés (anti-overflow). Aucun paiement → rien (l'état vide de la section porte déjà le message).
- **Zéro nouvelle requête Firestore** : réutilise `leasePaymentsProvider` + `lease.paymentDay`. Jetons de design uniquement, i18n FR/EN. TDD (4 tâches). `flutter analyze` clean, suite complète verte (2894).

### PR #174 — Dashboard : KPI patrimoniaux (occupation, patrimoine) + retrait des doublons (2026-09-09, commit b2d08d5)
- La grille KPI faisait doublon avec le panneau « À traiter / À venir » (#171). Nouvelle grille : **Taux d'occupation · Patrimoine · Documents en attente**. Loyers/retards/renouvellements retirés.
- Occupation = biens loués/total (ton warning si vacant) ; Patrimoine = Σ prix d'achat renseignés (montant à l'achat, factuel) ; tap → `/properties`. Cas dégradés gérés (0 bien, prix manquants).
- `dashboardPortfolioKpisProvider` dérive `propertiesListItemsProvider` (`activeLeaseId` + `purchasePriceCents`) — zéro nouvelle requête Firestore. `KpiGrid` passe en `ConsumerWidget`.
- i18n FR/EN. TDD (3 tâches). Suite complète verte (2875).
- Effet de bord : cette PR **retire le KPI « Baux à renouveler »** que la PR #172 venait justement d'aligner sur 60 j → `DashboardRepository.fetchRenouvellements` n'a plus de consommateur UI (candidat au nettoyage, hors périmètre).
- Différé (spec B) : indicateur factuel de fiabilité de paiement locataire (alternative légale à la notation).

### PR #172 — FIX Dashboard : KPI « Baux à renouveler » aligné sur la fenêtre 60 j (2026-09-09, commit 1ad8662)
- Le KPI comptait les baux finissant sous **30 j** alors que son drill-down (`/leases?filter=renewable`) et le panneau « baux finissant » (PR #171) utilisent **60 j** (`isLeaseRenewable`) : le compteur pouvait différer de la liste affichée juste en dessous. Suivi laissé ouvert par la PR #171, désormais fermé.
- `kLeaseRenewalWindowDays = 60` introduit dans `lease_renewal.dart` comme seuil unique ; `isLeaseRenewable` s'y réfère.
- `fetchRenouvellements` interroge la fenêtre 60 j (via la constante) avec borne haute **stricte** (`isLessThan`) pour coller à `isLeaseRenewable` (`inDays < 60`). Borne basse `endDate >= today` conservée (un bail déjà expiré n'est pas « à renouveler » — il ressort en retard).
- Sous-titre du KPI : « 30 prochains jours » → « 60 » (FR + EN).
- Tests de bornes ajoutés (`fetchRenouvellements` : 45 j compté, 59 j inclus / 61 j exclu, expiré et terminé exclus), écrits en TDD. `flutter analyze` clean, suite complète verte (2879).

### PR #171 — Dashboard : panneau « À traiter / À venir » à la place du graphe cash-flow (2026-09-08, commit 9b5682c)
- Le graphe cash-flow (peu utile sans crédit/dépenses saisis) est remplacé par un panneau actionnable `ActionItemsPanel` : bandeau encaissements du mois (encaissé/attendu/reste dû + barre), loyers en retard (tap → `/leases?filter=late`), baux finissant < 60 j (tap → `/leases?filter=renewable`), max 3/catégorie + « Voir tout », état vide « Tout est à jour ✓ ».
- Graphe déplacé plus bas dans `CollapsibleCashflowSection` (ExpansionTile fermé par défaut, lazy — `MonthlyCashflowChart` inchangé). Nouvel ordre : KPI → rentabilité portfolio → panneau → graphe repliable → activité récente.
- Zéro nouvelle requête Firestore : dérive `leasesListProvider` (même source que l'écran Baux) + `LoyersMoisKpi`. Helper `isLeaseRenewable` (seuil 60 j) extrait de `leases_filter_provider` et partagé → panneau et filtre « renouvelable » montrent les mêmes items. Priorité FEAT-028 (late > renewable) respectée.
- i18n FR + EN (14 clés). Développé en TDD (6 tâches, revues + revue finale whole-branch APPROVE). Suite complète verte (2874).
- Différé v2 : régularisations de charges dues. Suivi séparé : réconcilier le KPI « Baux à renouveler » (encore 30 j) avec la fenêtre 60 j.

### PR #170 — FIX: espaces manquants autour du lien de confidentialité (vitrine) (2026-09-08)
- Le lien « politique de confidentialité » apparaissait collé au texte sur la vitrine (« La<a>…</a>détaille » à propos ; « dans la<a>… » mentions légales).
- Cause : `<a>` inline placé sur sa propre ligne → Astro (whitespace type JSX) trim les sauts de ligne autour de l'élément, supprimant les espaces au build.
- Correctif : espace explicite `{' '}` autour du lien (`site/src/pages/a-propos.astro`, `site/src/pages/mentions-legales.astro`).
- Audit du HTML construit de toutes les pages : aucun autre lien de prose collé (les `</a><a>` de nav/footer sont des éléments flex, non concernés).

### PR #169 — FIX: boutons d'action de carte alignés et confortables (2026-09-08, commit 7b021bb)
- Retour recette : actions d'une carte de quittance (PDF/partage/annuler) désalignées ; « View lease »/« Edit » des cartes de bien sans padding vertical → cibles tactiles ~28 px, désagréables sur mobile.
- Cause : les 4 pieds de carte (bien/bail/locataire/quittance) copiaient le même `OutlinedButton.styleFrom` compact (`minimumSize: Size.zero`, `tapTargetSize.shrinkWrap`) ; la carte quittance mêlait ce bouton texte à des IconButton de hauteurs différentes.
- Correctif : composant partagé `CardActionButton`/`CardActionIconButton` (`lib/core/ui/cards/card_action_button.dart`), hauteur commune 40 px (`kCardActionButtonHeight`). Migration des 4 pieds + `ShareReceiptButton`. `mainAxisExtent` des grilles remonté (208→220, 232→244) pour éviter l'overflow.
- Tests : suite complète verte (2862).

### PR #168 — Design system : harmonisation boutons et icônes (2026-09-08, commit 45b66f9)
- Audit design-system (« icônes/boutons pas alignés ou hors système ») + correctif à la racine. Le thème centralisait `FilledButton` + couleurs mais laissait des trous → style ad-hoc par écran.
- **Boutons** : ajout `outlinedButtonTheme` + `textButtonTheme` dans `AppTheme` (rayon 4, gabarit, texte olive w600, même langage que FilledButton) → boutons secondaires/tertiaires cohérents sans toucher les sites d'appel (17 `OutlinedButton.styleFrom` inline divergents rendus superflus).
- **Icônes** : nouveau jeton `lib/core/ui/theme/app_icon_size.dart` (`AppIconSize` xs/sm/md/lg/xl/hero). Aberrations normalisées : `size: 11` → xs (14) ; états vides à 48 **et** 56 unifiés à hero (48) sur 5 écrans.
- **Couleurs** : seuils rendement/cash-flow vert/orange en dur (`Colors.green/orange.shade700`) → jetons `AppColors.success/warning.solid` (carte rentabilité bien + résultats simulateur), repli `?? AppColors.light`.
- Hors périmètre (documenté) : PdfColors, ombres/scrims alpha, teal « charges récupérables » (couleur catégorielle), migration des 510 `SizedBox`/247 `EdgeInsets` littéraux vers `AppSpacing`.
- Tests : suite complète verte (2862), `flutter analyze` clean.

### PR #166 — FIX: annulation et partage de quittance — état scopé par quittance (2026-09-08, commit 54a2bd9)
- Audit demandé après #165 : le **même anti-pattern** (provider-contrôleur global consommé par un widget rendu par ligne) existait pour `voidReceiptControllerProvider` (annuler) et `shareReceiptControllerProvider` (partager). Dans les deux vues liste (`receipts_card_view` = `CardGrid.builder`, `receipts_timeline_view` = `ListView.builder`), N `ReceiptCard`/`ReceiptActionsMenu`/`ShareReceiptButton` sont montés : annuler mettait le bouton en attente sur chaque carte + un SnackBar par carte ; partager allumait le spinner sur tous les boutons de partage.
- Correctif : les deux providers passent en `.family` keyés par `receiptId` ; tous les `watch`/`listen`/`read` des 3 widgets keyés par `receipt.id`. État isolé par quittance.
- Audit : reste de l'app sain — `deleteDocumentController`/`updateDocumentCategoryController` déjà `.family` keyés ; les `*FormController` sont sur des écrans mono-instance ; locale/theme/rail/viewMode/anonExpiry non concernés.
- Tests : `share_receipt_button_test` (2 boutons → 1 spinner), `void_receipt_controller_test` (nouveau) + `share_receipt_controller_test` (actionner r-1 laisse r-2 idle) ; existants adaptés à la clé `family`.

### PR #165 — FIX: génération de quittance — spinner et aperçu scopés au paiement cliqué (2026-09-07, commit 195cded)
- `generateReceiptControllerProvider` était un `StateNotifierProvider` **global** partagé par tous les boutons « Générer une quittance » de la liste de paiements (un `GenerateReceiptButton` par ligne), qui faisaient à la fois `watch` et `listen` dessus. Deux bugs recette : (1) au clic, `submitting` allumait le spinner sur **chaque** ligne du bloc ; (2) au `success`, le `ref.listen` de **chaque** bouton monté ouvrait un `ReceiptPreviewDialog`, d'où autant de dialogues empilés que de lignes visibles et plusieurs clics pour tout fermer.
- Correctif : provider passé en `.family` keyé par `paymentId` — chaque ligne a sa propre instance d'état ; spinner et dialogue sont scopés au paiement réellement cliqué. `submitFromPeriod` (défini mais jamais appelé) conservé tel quel.
- Tests : 2 cas ajoutés (`test/widget/generate_receipt_button_test.dart`) montent deux boutons côte à côte et vérifient un seul spinner + un seul `dialog_receipt_preview` ; ils échouaient avant (2 dialogues détectés), passent après.

### FEAT-050 — Site vitrine baillan.com (v1) (2026-09-06, PR #160)
- Site statique Astro dans `site/`, crawlable (HTML sans JS exécutable) — l'app Flutter reste inindexable (CanvasKit peint le texte dans un canvas). 5 pages FR : accueil, FAQ (20 Q/R recopiées de l'app + JSON-LD FAQPage), à propos, mentions légales (encadré « à compléter » : structure juridique inexistante), suppression de compte.
- **Écosystème couleur unique** : les 19 couleurs deviennent une source canonique `config/theme_tokens.json` → générateur Dart `tool/gen_theme_tokens.dart` → 2 miroirs générés `lib/core/theme/app_palette.g.dart` (délégué par `AppTheme`, valeurs inchangées, verrouillées par test) et `site/src/styles/tokens.css`. Garde-fou CI `scripts/check-theme-tokens.sh`.
- **Firebase Hosting** : 2 cibles ajoutées (`marketing` prod, `marketing-stage`), déploiements scopés `--only`. Cible marketing prod en `X-Robots-Tag: noindex` **transitoire** (retiré par le futur runbook de bascule). App passée en noindex global (`web/robots.txt` `Disallow: /`, `web/sitemap.xml` supprimé, meta robots `noindex` inconditionnel). Job CI `site` (build Astro) ajouté.
- **Hors périmètre** (runbook séparé) : bascule de domaine — DNS, domaines autorisés Firebase Auth, URL Play Console, resserrage `PROD_ORIGINS`. Passe de fond `docs/SEO.md` et `docs/ENVIRONMENTS.md` encore à faire.

### PR #161 — FIX: test du graphique de cash-flow indépendant de la date (2026-09-06, commit 66e60fe)
- `monthly_cashflow_chart_test.dart` échouait depuis que le calendrier a dépassé août 2026, sans changement de code de production : le fake de loyers `_makeRent` datait ses mois en dur (`2026, mois 1..6`) alors que `monthlyCashflowProvider` fenêtre les dépenses relativement à `DateTime.now()`. L'intersection s'est vidée du mois de la dépense de test, la mention « Aucune dépense saisie » réapparaissait. `_makeRent` rendu now-relatif. Bombe à retardement qui cassait toute PR vers `develop`.

### PR — FIX: navigation — tout changement d'onglet ramène à la racine (2026-08-11, commit 49d6069)
- Renversement de décision produit (2026-08-11). Depuis FEAT-026 (2026-07-03), changer d'onglet conservait l'état de la branche (pile navigation, position scroll, filtres) via `indexedStack`. Le propriétaire la juge fautive sur TOUS les onglets (pas seulement Profil comme ponctuellement testé le 2026-08-10) : cliquer Profil puis Home puis Profil rouvrait la sous-page au lieu du hub.
- Implémentation : `goBranch(index, initialLocation: true)` systématique vers la racine de chaque branche (à changer d'onglet). L'indexedStack et son State subsistent pour une racine jamais quittée en profondeur, donc les filtres (`StateProvider` non-autoDispose) et le scroll d'une racine non-pourvue de sous-page survivent quand même (conséquence mécanique, non un oubli).
- Résidu : flash visuel subsiste (non résolu, reporté par le propriétaire).

### PR — FIX: storage.rules — plafond d'upload 10 Mio → 50 Mio (palier max) (2026-08-08, commit c302210)
- Garde-fou anti-abus : `storage.rules` plafondait tous les uploads à 10 Mio, quel que soit le palier. Les 25 Mio (Max) et 50 Mio (Ultra) étaient donc INATTEIGNABLES : la règle refusait le fichier avant même que `createDocument` ne puisse valider le plafond du palier.
- **Pourquoi le plafond ne peut pas être différencié par palier dans storage.rules** : la règle Storage lit Firestore sur la base `(default)` exclusivement. Avec ADR 0003 (prod=`(default)`, staging=`staging`), un doc landlord en staging serait illisible → aucun palier ne peut être dérivé de manière fiable. Le bucket est partagé. Donc la règle doit couvrir le maximum de **tous** les paliers, le contrôle fin étant déléggué à `createDocument` (functions).
- Palier appliqué : `assertRealSizeWithinPlan()` dans le callable, qui lit la taille RÉELLE (métadonnées Storage) sans jamais faire confiance à la déclaration client. Fichier refusé → orphelin Storage immédiatement purgé.

### PR — FIX: profile.email nullable, écran profil ne casse plus (2026-08-08, commit d7d56cc)
- `LandlordProfile.email` était `required String`. Un doc `landlords` portant `email: null` (cas : compte anonyme upgradé avant la fix du callable) faisait échouer `fromJson` entièrement, et l'écran Informations personnelles affichait une erreur sans issue : « Impossible de charger le profil ».
- Correction : `email: String?` (nullable) + fallback UI sur Firebase Auth (source de vérité unique). Le champ est immuable, l'email ne peut être changé que par les administrateurs (le signaler au propriétaire si besoin).

### PR — FIX: finalizeAnonymousUpgrade renseigne email et nom depuis Auth (2026-08-08, commit 2e3c762)
- **Bug critique** : callable n'écrivait ni `email` ni `fullName` lors de la transition anonyme → compte complet. Le doc anonyme porte ces champs vides par construction (`email: null`, `fullName: ''`), et le callable les laissait intacts. Résultat : un compte complet sans identité — dashboard affiche « Hello » sans nom, écran Profil en erreur (voir fix d7d56cc).
- **Correction** : fonction pure `resolveUpgradeIdentity(authUser, current)` qui lit l'identité depuis Firebase Auth (niveau supérieur `email`/`displayName` puis chaque entrée de `providerData` — sur un `linkWithPopup` Google, le displayName peut être `undefined` en haut mais présent chez le fournisseur). Logique : **ne réécrit jamais par-dessus une valeur déjà renseignée** (un upgrade rejoué ne corrompt pas un nom édité depuis). Dernier repli du nom : l'email (« mieux qu'un champ vide »).
- Garde ajoutée : vérifie qu'un provider est effectivement lié (`providerData.length > 0`) — un anonyme pur ne peut plus invoquer le callable et fake un upgrade sans lier de provider.

### FEAT-056 : Abonnements multi-paliers Pro/Max/Ultra — implémentation back-end + client partiel (2026-08-02, branche `feat/056-multi-tier-subscriptions`)
- Modèle de données : `planLevel ∈ {pro, max, ultra | null}` + `entitlements` map additifs sur `landlords/{uid}` (gelés client, écrit Admin SDK seul).
- Quotas différenciés par palier effectif (3 tiers × 2 périodicités), définis dans source canonique `config/entitlements.json` (Dart/TS générés).
- **Back-end** ✅ : callables `createCheckoutSession` (3 paliers), `manageSubscription` (cancel/reactivate/change_plan), `createScenario` (quota enforce). Webhook + cron multi-paliers.
- **Quotas appliqués** : properties (0/2/5/15/∞), tenants (0/3/8/20/∞), activeLeases (0/2/5/15/∞), documents (0/10/50/150/∞), scenarios (1/3/15/30/∞), documentMaxBytes (0/10M/10M/25M/50M).
- **Paliers vendables** : Pro seul (`purchasable:true`) ; Max/Ultra démo UI (`purchasable:false`, erreur `level_not_purchasable`). RevenueCat/Stripe inactifs pour max/ultra.
- **Changement structural** : `investment_scenarios/create` passé à `if false`, création CF-exclusive (callable `createScenario`). Gating derniers quotas par serveur.
- État : ✅ toutes les fonctions implémentées, non mergé. UI Pro UI non construite (FEAT-044e). État docs (`docs/state/`) mis à jour.

### PR #145 : FEAT-054 — ADR 0003 — isolation Firestore prod/staging implémentée (2026-07-25)
- Base Firestore nommée `staging` déclarée (`firebase.json`), séparée de `(default)` prod.
- Flutter : `firestoreProvider` (`lib/core/config/firestore_provider.dart`) route vers `staging` (web staging uniquement) vs `(default)` (fail-safe pour émulateur + prod + mobile).
- Backend : helper `dbForRequest(request)` route par en-tête `Origin` (callables), `dbForLandlordUid(uid)` route webhook RevenueCat par présence du doc landlord (fail-safe prod d'abord).
- CI check `scripts/check-db-isolation.sh` : interdit `FirebaseFirestore.instance` hors provider/main.dart, et `admin.firestore()`/`getFirestore()` hors du routing.
- État : ✅ les shards `functions/account.md` et `functions/README.md` mis à jour pour documenter les patterns ADR 0003.

### PR #148, #151 : FEAT-055 — Comparaison de scénarios de simulation, entrée visible + responsive (2026-07-24, 2026-07-27)
- Route `/simulator/compare` (query param `ids=`), page `ScenarioComparisonPage`.
- Responsive mobile (cartes) + desktop (table fluide).
- Feature gate : logique Pro intégrée dans la page, route pas encore gâtée (✅ ticket d'audit : FEAT-055 à terminer côté gate).
- État : ✅ statut FEATURES.md passé de `💡 idea` → `✅ done` ; route documentée dans `routes/simulator.md`.

### PR #152 : CI — déploiement de rules+indexes par base Firestore (2026-07-30)
- La CI déploie désormais rules+indexes **ciblés par base**, via la sortie
  `deploy_targets` de `determine-env` : `develop` → `hosting:stage,firestore:staging`,
  `main` → `hosting:prod,firestore:(default),storage`. Avant, seul le hosting
  partait par la CI et les rules étaient poussées à la main.
- ⚠️ **`--only firestore` sans filtre est INTERDIT** : la CLI viserait les DEUX
  bases, donc la prod depuis `develop`. C'est précisément ce que le ciblage par
  base empêche. Vérifié en `--dry-run` : sans filtre les logs sortent en double.
- Storage : depuis `main` seulement (bucket unique partagé).
- Cloud Functions restent hors CI (déploiement manuel délibéré, ADR 0003).
- Contournement du retry-race Hosting resserré : il ne s'applique plus que si
  TOUTES les erreurs du log sont cette race, sinon un échec de rules serait
  masqué en CI verte.
- Impact code applicatif : zéro ; pur workflow.


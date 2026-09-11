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

## Changements (2026-08-03 → 2026-09-06)

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


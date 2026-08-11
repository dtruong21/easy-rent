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

## Changements (2026-08-03 → 2026-08-11)

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


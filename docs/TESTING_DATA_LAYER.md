# Tester la couche `lib/**/data/` (dépôts concrets)

> Origine : angle mort de test relevé pendant FEAT-056. Une suite complète peut
> rester verte alors qu'une écriture client est refusée en production, parce que
> les deux moitiés du contrat (règles Firestore / chemin d'écriture du dépôt)
> sont testées séparément et que **leur désaccord n'est testé nulle part**.

## 1. Recensement — état de la couverture

Dépôts concrets qui écrivent dans Firestore et/ou appellent des callables.
« Transport » = comment l'écriture atteint le backend.

| Dépôt (`lib/features/…/data/`) | Collection | Transport des écritures | Test instanciant la classe concrète | Ce que le test couvre |
|---|---|---|---|---|
| `property_repository.dart` | `properties` | create + delete → callable ; **update direct** | ✅ `property_repository_firestore_test` | lecture seule (`list`, `listWithLeases`) |
| `tenant_repository.dart` | `tenants` | create + delete → callable ; **update direct** | ✅ `tenant_repository_firestore_test` | lecture seule (`listWithActiveLeases`) |
| `lease_repository.dart` | `leases` | 100 % callables | ✅ `lease_repository_firestore_test` | lecture seule (`listForDisplay`) |
| `payment_repository.dart` | `payments` | 100 % callables | ❌ **aucun** | — |
| `receipts_repository.dart` | `receipts` | 100 % callables | ⚠️ `receipts_repository_payment_notes_test` | `renderPdfBytes` seul (PDF, ni Firestore ni callable) |
| `documents_repository.dart` | `documents` | 100 % callables (+ Storage) | ❌ **aucun** | — |
| `expenses_repository.dart` | `expenses` | 100 % callables | ❌ **aucun** | — |
| `investment_scenario_repository.dart` | `investment_scenarios` | **create + update directs** ; softDelete → callable | ✅ **ajouté** (cf. §4) | écritures + transport |
| `dashboard_repository.dart` | (lecture transverse) | — | ✅ `dashboard_repository_firestore_test` | lecture seule (`fetchRetards`) |
| `support_repository.dart` | `support_requests` | **create direct** | ✅ `support_repository_firestore_test` | `submit` (écriture) |
| `auth_repository.dart` | `landlords` | callables `finalizeAnonymousUpgrade`, `deleteAccount` | ✅ 6 fichiers | flux auth + callables |
| `profile_repository.dart` | `landlords` | direct | ❌ **aucun** | — |
| `landlord_tier_repository.dart` | `landlords` | direct | ❌ **aucun** | — |
| `paid_plan_interest_repository.dart` | `paid_plan_interest` | direct | ❌ **aucun** | — |

### Constat principal

Avant ce ticket, **une seule écriture Firestore métier était couverte par un test
sur classe concrète** (`support.submit`), plus les callables d'auth. Tous les
chemins de création/mise à jour/suppression de `properties`, `tenants`, `leases`,
`payments`, `receipts`, `documents`, `expenses` — c'est-à-dire l'essentiel du
produit — n'étaient exercés par aucun test au niveau du dépôt réel. Les tests
concrets existants sont tous des tests de **lecture**.

Le cas `investment_scenarios` est le plus exposé : c'est la **seule collection
métier qui autorise encore la création directe depuis le client**
(`firestore.rules` §`investment_scenarios`), donc la seule dont le transport peut
diverger des règles sans qu'un backend s'y oppose.

## 2. Pourquoi la suite reste verte — l'angle mort structurel

Trois couches de tests existent, chacune valide une moitié du contrat :

| Couche | Ce qu'elle valide | Ce qu'elle ne peut pas voir |
|---|---|---|
| Tests contrôleurs/widgets (`scenario_limit_controller_test`, `simulator_page_test`…) | logique métier via l'**interface abstraite** + faux in-memory | l'implémentation concrète n'est jamais instanciée |
| Tests dépôt concret (`fake_cloud_firestore`) | requêtes, mapping, payloads | `fake_cloud_firestore` **n'évalue pas `firestore.rules`** — une écriture interdite y réussit |
| Tests de règles (`functions/rules-tests/`) | les règles, seules | ne regardent jamais ce que le client fait réellement |

Aucune ne compare **ce que le client écrit** à **ce que les règles autorisent**.
C'est ce joint qui a lâché.

## 3. Stratégie retenue — 3 niveaux

### Niveau 1 — Test unitaire du dépôt concret (rapide, par défaut)

`fake_cloud_firestore` + `firebase_auth_mocks` + un **`FirebaseFunctions`
enregistreur**. Le pattern `_UnusedFunctions` déjà utilisé dans le projet fait
échouer tout appel de callable ; sa variante `_RecordingFunctions` enregistre le
nom et les arguments, ce qui permet d'asserter **quel transport** le dépôt a
choisi — la propriété qui a cassé en FEAT-056.

Coût : nul (dépendances déjà présentes), exécution en millisecondes. À appliquer
à tous les dépôts du tableau §1 marqués ❌.

### Niveau 2 — Verrou de conformité règles ↔ dépôts (le vrai filet)

Un test qui lit `firestore.rules`, en extrait les conditions `allow` par
collection, et les confronte à une matrice déclarée des écritures directes du
client. Il devient rouge dès que l'une des deux moitiés bouge sans l'autre.

Le projet a déjà un précédent pour ce type de scan source :
`firestore_query_conformance_test.dart` (piège `isEqualTo: null`). Même logique,
même coût — pas d'émulateur, pas de réseau, tourne dans la CI existante.

### Niveau 3 — Émulateur, pour l'application réelle des règles (ciblé)

`npm run test:rules` dans `functions/` (émulateurs Firestore + Storage + vitest) est
le seul endroit où les règles sont réellement évaluées. `investment_scenarios` y était
couvert pour le **list-scoping** seulement (via `LANDLORD_SCOPED_COLLECTIONS`) ;
ses écritures ne l'étaient pas — c'est ajouté par ce ticket (cf. §4).

À réserver aux invariants de sécurité (isolation cross-user, immuabilité de
`landlordId`, refus des écritures serveur-only) — pas au mapping de payload, trop
lent pour ça.

> ℹ️ **Cette suite tourne bien en CI**, dans un job dédié `firestore-rules`
> (« Firestore Rules (cross-user) ») de `.github/workflows/ci.yml`, séparé du job
> `functions` : `npm test` utilise la config vitest par défaut, qui n'inclut que
> `src/**/*.test.ts`, donc `rules-tests/` a besoin de sa propre étape (JDK +
> émulateur, avec cache du jar). Attention en lisant une branche ancienne : ce
> job a été ajouté sur `develop` et n'existe pas sur `main`, donc un `grep` dans
> `.github/` depuis une branche en retard conclut à tort qu'il n'y a rien.

> Recommandation de séquencement : niveaux 1 + 2 d'abord (gratuits, attrapent la
> régression de FEAT-056), niveau 3 ensuite pour `investment_scenarios` et les
> collections sans test de règles.

## 4. Ce qui est implémenté dans ce ticket

### `test/unit/investment_scenario_repository_firestore_test.dart` (10 tests)

Première couverture de `FirestoreInvestmentScenarioRepository` : `create`
(persistance, hydratation, trim, champs exigés par les règles — `id`,
`schemaVersion`, `scenarioJson`), `list`/`getById` (exclusion soft-delete et
cross-landlord), `update` (synchro `scenarioJson` ↔ champs root), et surtout le
**transport** : `softDelete` doit passer par la callable `softDeleteEntity`,
`create`/`update` ne doivent invoquer aucune callable.

### `test/unit/firestore_write_path_conformance_test.dart` (4 tests)

Le verrou du niveau 2. Confronte `firestore.rules` à la matrice
`_clientDirectWrites`, et re-dérive cette matrice depuis les sources pour
qu'elle ne périme pas en silence.

**Vérifié par mutation** : en passant `investment_scenarios` à
`allow create: if false` (la situation exacte de FEAT-056), ce test devient rouge
avec un message actionnable, pendant que `scenario_limit_controller_test` et les
tests de dépôt du niveau 1 restent verts — ce qui démontre à la fois la
régression et la raison pour laquelle le niveau 1 seul ne suffit pas.

### `functions/rules-tests/firestore_rules.test.ts` (+25 tests, 33 → 58)

Le niveau 3 pour `investment_scenarios` : `create` (payload valide, compte
anonyme autorisé, non-authentifié refusé, création pour autrui, `id` ≠ docId,
`deletedAt` pré-rempli, nom vide / > 120, `schemaVersion` non-int / ≤ 0,
`scenarioJson` non-map), `update` (immuabilité `landlordId`/`createdAt`,
soft-delete client refusé, doc déjà soft-deleted), `delete` (refus systématique),
`get` (non-régression).

Chaque test d'écriture **négatif** utilise son propre doc jetable : avec un doc
partagé, une régression de rule laisse la mutation passer et corrompt le doc, ce
qui fait cascader les tests suivants en faux négatifs et désigne le mauvais
coupable. Vérifié par mutation (ouverture de `delete` + retrait de
`preservesImmutables` → exactement 4 échecs, sans cascade).

## 5. Reste à faire

- Niveau 1 pour `payments`, `documents`, `expenses`, `receipts` (chemins
  callables), `profile`, `landlord_tier`, `paid_plan_interest`.
- Étendre la matrice `_clientDirectWrites` si de nouvelles collections
  apparaissent — le test `chaque collection déclarée a un bloc de règles et un
  dépôt` échoue si une entrée pointe dans le vide, mais une collection **jamais
  déclarée** reste invisible.

# Plan — [FEAT-036] Charges récupérables / non-récupérables

> **Statut** : Plan d'architecture (2026-07-05). Effort estimé : **S (~1,5–2 j)**.
> **Stack** : Firebase — Firestore + Cloud Functions (TypeScript/Node 20) + Flutter Web. **PAS Supabase.**
> **Dépend de** : FEAT-005 (CRUD baux) ✅, FEAT-029 (régularisation) ✅, FEAT-014 Phase 3 (champs bail) ✅.
> **Spec** : [`../backlog/036-charges-recuperables.md`](../backlog/036-charges-recuperables.md).

## Summary

On ajoute au bail un champ **`nonRecoverableChargesCents`** (int, défaut 0) à côté du `chargesAmountCents`
existant, **réinterprété comme la part récupérable** (provision mensuelle facturable au locataire). Le total
affiché de charges devient `chargesAmountCents + nonRecoverableChargesCents`. Point de bascule architectural
majeur, détaillé plus bas : **la régularisation FEAT-029 est déjà conforme sans changement de calcul**, car
elle régularise `payments.chargesAmountCents` (les provisions réellement encaissées via les quittances), et
cette provision découle de `lease.chargesAmountCents` = le récupérable. Le non-récupérable est une charge
bailleur qui ne transite **jamais** par le locataire (décret 87-713) : purement informatif sur le bail (fiche,
futurs documents). Migration triviale (champ absent ⇒ traité comme 0). Aucun impact index Firestore.

**Découvertes clés lors de l'analyse** (écarts / points structurants) :

1. **La régularisation ne lit PAS `lease.chargesAmountCents`.** Elle somme `payments.chargesAmountCents`
   (`charge_provisions_calculator.dart` → `sumChargeProvisionsForPeriod`), c.-à-d. les provisions réellement
   encaissées mois par mois via les paiements/quittances. Ces provisions sont pré-remplies depuis
   `lease.chargesAmountCents` (`payment_form_page.dart` L81/L96). **Conséquence : dès lors qu'on définit
   `lease.chargesAmountCents` = récupérable, AC-2 (« seul le récupérable entre dans le solde ») est satisfait
   par construction**, sans toucher le calcul ni le PDF de régularisation. Le renderer et le balance object
   documentent d'ailleurs déjà « ne mélange QUE les charges récupérables » — l'intention était là, il manquait
   juste le champ non-récupérable côté bail.

2. **Un champ « non récupérable » existe déjà, mais ailleurs et pour un autre usage** :
   `properties.condoFeesNonRecoverableCents` (charges de copropriété non récupérables, saisi sur le BIEN,
   consommé par le calcul de rentabilité `core/finance/profitability.dart` et le simulateur). **Ne pas
   confondre** avec `leases.nonRecoverableChargesCents` (ventilation des charges DU BAIL). Ce sont deux notions
   distinctes qui coexistent — voir Risques. FEAT-036 ne touche pas `condoFeesNonRecoverableCents`.

3. **Format Firestore = camelCase** (les modèles Dart sont annotés snake_case et traversent
   `firestoreDocToSnakeJson`, qui convertit récursivement camelCase↔snake_case y compris les sous-maps). Le
   contrat réel de `leases` est bien : `landlordId`, `rentAmountCents`, `chargesAmountCents`, `status ∈
   {active, terminated, archived}`, etc. — cf. `functions/src/callable/lease_payment.ts` (source de vérité,
   `SCHEMA.md` est périmé).

---

## a) Modèle de données

### Décision : DEUX champs plats (recommandé), PAS de sous-map

`leases` porte aujourd'hui `chargesAmountCents` (int, provision mensuelle unique). On ajoute **un** champ :

| Champ | Type | Défaut | Sémantique | Écrit par |
|---|---|---|---|---|
| `chargesAmountCents` | int | 0 | **Réinterprété** : part **récupérable** (provision mensuelle facturable au locataire) | `createLease`/`updateLease` |
| `nonRecoverableChargesCents` | int | 0 | Part **non récupérable** (à la charge du bailleur — informatif) | `createLease`/`updateLease` |

- **Total charges** (partout où on l'affichait) = `chargesAmountCents + nonRecoverableChargesCents`, exposé via
  un getter Dart `LeaseExtension.totalChargesCents` (nouveau) et un getter TS côté receipts si besoin.
- **`chargesAmountCents` est CONSERVÉ** (pas renommé, pas supprimé). C'est le pivot rétrocompat : tout le code
  qui le lit aujourd'hui (quittance, provision du paiement, dashboard) continue de lire **le récupérable**, ce
  qui est le comportement juridiquement correct (on ne facture au locataire que du récupérable).

**Pourquoi deux champs plats et pas la sous-map `charges: { recoverable, nonRecoverable }`** :

- **Rétrocompat maximale à coût nul** : garder `chargesAmountCents` tel quel = zéro migration sur ce champ,
  zéro réécriture des ~15 points de lecture existants (quittance, payments, dashboard, cards). Une sous-map
  imposerait de migrer *tous* les baux et de réécrire *tous* les accès (`chargesAmountCents` → `charges.recoverable`).
- **`firestoreDocToSnakeJson` gère mal les sous-maps sans friction** : une sous-map `charges` deviendrait
  `charges: { recoverable, non_recoverable }` côté Dart, ce qui force un sous-modèle freezed imbriqué
  (`@JsonKey` nested) et un mapping manuel — surcoût de codegen et de tests pour aucun gain.
- **Cohérent avec le style du projet** : les montants du bail sont déjà tous plats
  (`rentAmountCents`, `depositAmountCents`, `agencyFeesCents`, `chargesAmountCents`). Un champ plat de plus
  respecte la convention « trois colonnes plates valent mieux qu'une map polymorphe » (CLAUDE.md : *default to simple*).

**Naming** : `nonRecoverableChargesCents` (et non `chargesNonRecoverableCents`) pour lire naturellement
« non-recoverable charges ». En Dart : `@JsonKey(name: 'non_recoverable_charges_cents')` (traversée
`firestoreDocToSnakeJson` ⇒ champ Firestore `nonRecoverableChargesCents`, cohérent avec le reste). Le
récupérable **n'est pas renommé** en `recoverableChargesCents` pour ne pas casser la rétrocompat ; il est
seulement **relabellisé** dans l'UI (« Charges récupérables »).

### Index Firestore (`firestore.indexes.json`)

**Aucun impact.** `nonRecoverableChargesCents` n'est jamais un critère de `where`/`orderBy` (montant affiché,
pas filtré). Aucun index à ajouter/modifier.

---

## b) Migration des baux existants

### Décision : dérivation lazy à la lecture (recommandé), PAS de script one-shot

**AC-3** : un bail pré-036 (`chargesAmountCents` seul, pas de `nonRecoverableChargesCents`) doit conserver son
montant, interprété comme **récupérable**, non-récupérable = **0**, sans perte ni régression.

- Le modèle Dart `Lease` déclare `nonRecoverableChargesCents` avec **`@Default(0)`** (même pattern que
  `agencyFeesCents`, `solidarityClause`). Un doc Firestore sans ce champ ⇒ `firestoreDocToSnakeJson` ne produit
  pas la clé ⇒ freezed applique le défaut `0`. **`chargesAmountCents` est déjà présent et inchangé** ⇒ il reste
  le récupérable. AC-3 est satisfait **sans écrire une seule ligne de migration**.
- Côté backend, `updateLease` accepte `nonRecoverableChargesCents` dans les champs mutables ; le premier
  ré-enregistrement du bail (édition) matérialisera le champ à sa vraie valeur. Jusque-là, l'absence = 0 partout.

**Pourquoi lazy et pas un script Admin SDK** :

- La valeur par défaut (récupérable = existant, non-récupérable = 0) est **dérivable sans ambiguïté** de l'état
  actuel : aucune information n'est perdue en différant l'écriture. Un backfill n'apporterait qu'un `= 0`
  explicite déjà couvert par le défaut freezed.
- Zéro risque opérationnel (pas de script cross-landlord à écrire, tester, exécuter une fois, monitorer). Le
  projet privilégie déjà cette approche (cf. FEAT-031 : `lastReminderPeriod` absent ⇒ traité comme jamais
  relancé, **aucun backfill**).
- **Contre-argument** (à surface, voir Décisions) : requêter/agréger un jour sur `nonRecoverableChargesCents`
  serait impossible tant que le champ est absent de certains docs (Firestore n'indexe pas les champs manquants).
  Non bloquant en V1 (le champ n'est jamais requêté), mais si un futur reporting l'exige, un script one-shot
  redeviendra pertinent. Décision par défaut : **lazy** ; script reporté à un besoin réel.

---

## c) Backend (Cloud Functions)

Fichier : **`functions/src/callable/lease_payment.ts`**. `leases` est **CF-exclusive** (rules interdisent tout
write client) → toute la validation vit ici.

### `createLease`

1. Lire `nonRecoverableChargesCents` (défaut 0) :
   ```ts
   const nonRecoverableChargesCents = requireInt(
     data.nonRecoverableChargesCents ?? 0,
     "nonRecoverableChargesCents",
     {min: 0},
   );
   ```
2. Ajouter `nonRecoverableChargesCents` au `tx.set(leaseRef, { ... })` (à côté de `chargesAmountCents`).
3. `chargesAmountCents` reste `requireInt(..., {min: 0})` inchangé (= récupérable).

### `updateLease`

- Ajouter `"nonRecoverableChargesCents"` à `LEASE_MUTABLE_FIELDS`.
- Le champ transite par la boucle générique `cleanPatch` (pas de transformation de type spéciale, comme
  `agencyFeesCents`). Validation de type/borne : voir ci-dessous.

### Cohérence total = récupérable + non-récupérable — décision

**Il n'y a PAS de champ « total » persisté à contraindre.** Le total est toujours dérivé
(`chargesAmountCents + nonRecoverableChargesCents`). Donc **aucune contrainte d'égalité `total = R + NR` à
valider** — c'est une non-question dans ce modèle (c'est justement l'avantage de garder `chargesAmountCents`
comme la part récupérable plutôt que comme un total). La seule validation backend nécessaire :

- `nonRecoverableChargesCents` : entier `>= 0` (via `requireInt`/`optionalInt` selon présence). Un
  helper de validation type/borne dans la boucle `updateLease` (comme le fait déjà `status`/`paymentMethod`)
  est nécessaire car `cleanPatch` passe la valeur brute : ajouter un check ciblé
  `if (cleanPatch.nonRecoverableChargesCents !== undefined) { assert int >= 0 }`.

> Si le PO préférait que `chargesAmountCents` reste le **total** (option écartée, voir Décisions à trancher),
> alors une contrainte `recoverable + nonRecoverable === chargesAmountCents` deviendrait indispensable ici, et
> il faudrait réécrire tous les points de lecture. C'est précisément ce qu'on évite.

### Tests backend (`functions/src/__tests__/`, vitest)

- `createLease` avec `nonRecoverableChargesCents` valide ⇒ doc contient le champ.
- `createLease` sans le champ ⇒ doc a `nonRecoverableChargesCents === 0` (défaut).
- `updateLease` patch `nonRecoverableChargesCents` ⇒ écrit ; patch négatif ⇒ `invalid-argument`.
- Non-régression : `chargesAmountCents` continue d'être validé/écrit à l'identique.

---

## d) Régularisation (FEAT-029)

### Décision : AUCUN changement de calcul ni de PDF (la V1 est déjà conforme)

Rappel du flux réel :
`lease.chargesAmountCents` (récupérable) → pré-remplit `payment.chargesAmountCents` → sommé par
`sumChargeProvisionsForPeriod` (provisions encaissées) → `ChargeRegularizationBalance` → PDF.

Puisque `chargesAmountCents` **devient officiellement le récupérable**, la chaîne entière ne régularise que du
récupérable. **`charge_provisions_calculator.dart`, `charge_regularization_balance.dart`,
`charge_regularization_form.dart` et `charge_regularization_pdf_renderer.dart` restent inchangés** (le PDF
mentionne déjà « Seules les charges de nature récupérable ont été prises en compte » — devient vrai *de jure*
en plus de *de facto*).

**Travail réel sur FEAT-029** = documentaire / durcissement léger :

- Mettre à jour le commentaire d'en-tête de `charge_regularization_balance.dart` (il référence
  `properties.condoFeesNonRecoverableCents` comme « le » non-récupérable ; préciser désormais que le
  non-récupérable **du bail** = `leases.nonRecoverableChargesCents`, distinct des charges de copro du bien, et
  qu'aucun des deux n'entre dans le solde régularisable).
- **Vérifier** que le pré-remplissage de la provision du paiement (`payment_form_page.dart`) reste basé sur
  `lease.chargesAmountCents` (le récupérable) — c'est déjà le cas, à conserver explicitement (ne PAS y ajouter
  le non-récupérable, sinon on facturerait de l'illégal au locataire et on fausserait la régularisation).

### Cas limite à couvrir en test

- Bail avec `nonRecoverableChargesCents > 0` : la régularisation calculée doit être **strictement identique** à
  un bail où ce champ vaut 0 (le non-récupérable est invisible du calcul). C'est le test de non-régression clé
  de l'AC-2.

---

## e) UI Flutter

### Modèle `Lease` (`lib/features/leases/domain/lease.dart`)

- Ajouter le champ :
  ```dart
  @JsonKey(name: 'non_recoverable_charges_cents')
  @Default(0)
  int nonRecoverableChargesCents,
  ```
- Étendre `LeaseExtension` :
  - `int get recoverableChargesCents => chargesAmountCents;` (alias lisible, optionnel mais clarifie l'intention).
  - `int get totalChargesCents => chargesAmountCents + nonRecoverableChargesCents;`
  - **`totalAmountCents`** (loyer CC) : passe de `rentAmountCents + chargesAmountCents` à
    `rentAmountCents + totalChargesCents`. ⚠️ **Décision loyer CC** (voir Décisions à trancher) : faut-il que le
    « loyer charges comprises » inclue le non-récupérable ? Le non-récupérable n'est **pas** facturé au
    locataire → le « loyer CC dû par le locataire » ne devrait PAS l'inclure. **Recommandation : `totalAmountCents`
    reste `rent + récupérable`** (comportement actuel préservé) ; le total des charges (R+NR) n'est affiché que
    comme information de ventilation, jamais comme montant dû. → concrètement, **ne pas modifier
    `totalAmountCents`**, ajouter seulement `totalChargesCents` pour l'affichage informatif.
- Régénérer `lease.freezed.dart` + `lease.g.dart` (`build_runner`). `dart format` obligatoire (CI).

### `LeaseForm` (`lib/features/leases/presentation/widgets/lease_form.dart`)

Section 2 « Loyer et charges » : dédoubler le champ charges.

- Renommer le champ charges existant : label **« Charges récupérables (€) »** (contrôleur `chargesController`
  inchangé → alimente `chargesAmountCents`). Helper : « Provisions mensuelles refacturables au locataire
  (décret n°87-713) ».
- **Nouveau champ** « Charges non récupérables (€) » (contrôleur `nonRecoverableChargesController`, `Key('field_non_recoverable_charges')`).
  Helper : « À la charge du bailleur — non refacturable au locataire. Saisir 0 si aucune. » Défaut vide ⇒ 0.
  Réutiliser le validateur montant `>= 0` (optionnel, comme `agencyFees`).
- Ajouter l'état `_nonRecoverableChargesTouched` et l'inclure dans `validateAll()`.

### `LeaseFormPage` (`lib/features/leases/presentation/lease_form_page.dart`)

- Déclarer/disposer `_nonRecoverableChargesCtrl` ; pré-remplir depuis
  `lease.nonRecoverableChargesCents` en édition (0 ⇒ champ vide).
- Dans `_submit()` : parser `nonRecoverableChargesCents` (vide ⇒ 0) et le passer au controller.

### `LeaseFormController` (`application/lease_form_controller.dart`)

- Ajouter le param `int nonRecoverableChargesCents = 0` à `submit(...)` ; le propager à `repo.create(...)` et au
  `initial.copyWith(...)` du mode édition.

### `LeaseRepository` (`data/lease_repository.dart`)

- `create(...)` : ajouter le param + `'nonRecoverableChargesCents': nonRecoverableChargesCents` au payload
  `createLease`.
- `update(Lease)` : ajouter `'nonRecoverableChargesCents': lease.nonRecoverableChargesCents` au `patch`.
- Mettre à jour le contrat de l'interface `abstract interface class LeaseRepository`.

### `LeaseDetailPage` (`lib/features/leases/presentation/lease_detail_page.dart`, section ~L418-443)

Aujourd'hui : « Charges » (= `chargesAmountCents`) + « Loyer CC » (= `totalAmountCents`).
Nouvelle ventilation :

- « Charges récupérables » = `chargesAmountCents`.
- « Charges non récupérables » = `nonRecoverableChargesCents` (afficher **toujours**, même à 0, pour lever
  l'ambiguïté — AC-4 « voit la ventilation »).
- « Total charges » = `totalChargesCents` (optionnel mais recommandé pour AC-4 « et le total »).
- « Loyer CC » = `totalAmountCents` (= loyer + récupérable, **inchangé** — montant réellement dû par le locataire).

### Cards / table baux — décision

`lease_card.dart` (L86) et `leases_table_view.dart` (L58/153) affichent `totalAmountCents` (« CC / mois »).
Puisqu'on ne modifie PAS `totalAmountCents` (reste rent + récupérable), **aucun changement requis** : la carte
continue d'afficher le loyer CC dû par le locataire. Cohérent et non-régressif.

### Quittance PDF & bandeau paiement — décision

- **Quittance PDF (`functions/src/callable/receipts.ts`)** : régularise/affiche `payment.chargesAmountCents`
  (récupérable) et `lease.chargesAmountCents` (récupérable, dans `computeDocumentType`). **Aucun changement** :
  la quittance ne doit facturer que le récupérable. Le non-récupérable **n'apparaît pas** sur la quittance
  (correct — il n'est pas dû par le locataire). Voir Décisions à trancher pour l'option « afficher la
  ventilation » (écartée).
- **`lease_context_banner.dart`** (L61/134/195, « X € CC/mois ») : lit `lease.chargesAmountCents` pour composer
  le total facturable. **Inchangé** (récupérable = ce qui est facturé). Non-régressif.

### Dashboard & rentabilité — décision

- `dashboard_repository.dart` (5 accès à `chargesAmountCents`) somme les loyers encaissés/dus : lit
  `payments.chargesAmountCents` (récupérable encaissé). **Inchangé** — le dashboard reflète les flux réels
  facturés, pas les charges bailleur. Non-régressif.
- `core/finance/profitability.dart` : consomme `properties.condoFeesNonRecoverableCents` (charges bailleur au
  niveau BIEN), **pas** le bail. Hors périmètre FEAT-036, **aucun changement** — mais à surface comme risque de
  confusion conceptuelle (deux « non-récupérable » distincts, voir Risques).

### Routes

**Aucune** nouvelle route (évolution de formulaires/fiche existants).

### Providers

**Aucun** nouveau provider (les contrôleurs existants gagnent un paramètre).

---

## f) Rétrocompat / non-régression — recensement des lectures de `chargesAmountCents`

Invariant garanti : **`chargesAmountCents` = part récupérable**, jamais renommé, jamais supprimé. Tous les
points ci-dessous continuent de lire le récupérable, ce qui est le comportement voulu (on ne facture que du
récupérable au locataire) :

| Point de lecture | Fichier | Rôle | Impact FEAT-036 |
|---|---|---|---|
| Provision quittance / totaux | `functions/src/callable/receipts.ts` (L225, L239) | somme provisions + `computeDocumentType` | **Aucun** (récupérable) |
| Pré-remplissage provision paiement | `lib/features/payments/presentation/payment_form_page.dart` (L81, L96) | seed charges du paiement | **Aucun** (récupérable) |
| Calcul régularisation | `charge_provisions_calculator.dart` (L50) via `payments.chargesAmountCents` | solde régularisable | **Aucun** (récupérable) |
| Dashboard (encaissé/dû) | `dashboard_repository.dart` (L77, L83, L229, L246, L287) | KPI + graphe via `payments` | **Aucun** (récupérable) |
| Card / table bail | `lease_card.dart` (L86), `leases_table_view.dart` (L58/153) via `totalAmountCents` | loyer CC affiché | **Aucun** (`totalAmountCents` non modifié) |
| Bandeau contexte paiement | `lease_context_banner.dart` (L61/134/195) | « X € CC/mois » | **Aucun** (récupérable) |
| Fiche bail | `lease_detail_page.dart` (L436, L442) | affichage | **Modifié** : ajoute ventilation R/NR + total |
| Property list item | `property_list_item.dart` (L73), `property_repository.dart` (L172) | denorm loyer sur card bien | **Aucun** (récupérable) |
| Détection retards | `lease_lateness.dart` (via `payments`) | grâce/couverture | **Aucun** (indépendant du montant) |

**Aucune régression attendue** : le seul montant qui change de définition sémantique est « total charges » sur
la fiche bail (désormais R+NR), volontairement introduit comme nouvelle information, et `totalAmountCents`
(loyer CC) est explicitement laissé inchangé.

---

## g) Sécurité / RGPD

**Résumé RLS en un paragraphe** (garde-fou projet) : `leases` reste **CF-exclusive** — les rules Firestore
interdisent déjà tout `create/update/delete` client (`allow write: if false`) et n'autorisent la lecture qu'au
propriétaire actif (`isOwner(landlordId) && resource non supprimée`). L'ajout du champ `nonRecoverableChargesCents`
**n'ouvre aucune surface** : il est écrit exclusivement par les callables `createLease`/`updateLease` (Admin SDK,
qui bypasse les rules après vérification `uid == landlordId`), et lu comme le reste du doc lease par son seul
propriétaire. **Aucune modification de `firestore.rules` ni de `firestore.indexes.json` n'est requise.**

**RGPD** : `nonRecoverableChargesCents` est une donnée financière du bail, même catégorie que les autres
montants déjà couverts par le consentement/export/effacement existants (`leases` est déjà dans le périmètre).
Aucune nouvelle catégorie de donnée personnelle, aucun impact sur consentement ou export. Pas de mention légale
supplémentaire sur la quittance (le non-récupérable n'y figure pas). La conformité **améliore** au contraire la
robustesse juridique de la régularisation (décret 87-713).

---

## Testing strategy

Mappé aux acceptance criteria (AC-1..5).

### Unitaires — Dart

- **`lease.dart`** (nouveau ou étendu) : `fromJson` sans `non_recoverable_charges_cents` ⇒ `0` (AC-3) ;
  avec valeur ⇒ lue ; `totalChargesCents == chargesAmountCents + nonRecoverableChargesCents` ; `totalAmountCents`
  **inchangé** (= rent + récupérable).
- **Régularisation (non-régression, AC-2/AC-5)** : étendre `charge_regularization_balance_test.dart` — un bail
  avec `nonRecoverableChargesCents > 0` produit **exactement** le même solde qu'avec 0 (le calcul ignore le
  non-récupérable). Test explicite « le non-récupérable n'entre pas dans le solde ».

### Unitaires — TypeScript (`functions/src/__tests__/`, vitest)

- `createLease` : champ absent ⇒ `0` (AC-3) ; valeur valide ⇒ écrite ; valeur négative ⇒ `invalid-argument`.
- `updateLease` : patch `nonRecoverableChargesCents` valide/négatif ; non-régression `chargesAmountCents`.

### Widget — Flutter

- **`LeaseForm`** (2 champs charges) : les deux champs présents (`field_charges`, `field_non_recoverable_charges`),
  saisissables ; `validateAll()` couvre le nouveau champ ; création avec R+NR (AC-1) ; édition pré-remplit les
  deux (0 ⇒ vide).
- **`LeaseDetailPage`** : affiche « Charges récupérables », « Charges non récupérables » (même à 0), « Total
  charges » (AC-4).
- Tester **web + mobile form factors** (formulaire partagé — cf. synergie FEAT-024).

### Non-régression manuelle (QA)

- Quittance PDF d'un bail avec non-récupérable > 0 : montant charges quittance = récupérable seul (AC-5).
- Dashboard KPI/graphe inchangés (AC-5).
- Card/table bail : « CC/mois » = loyer + récupérable (inchangé).
- Bail pré-036 (créé avant migration) : fiche affiche non-récupérable = 0, régularisation identique (AC-3).

---

## Risques

- **Confusion conceptuelle « deux non-récupérables »** (risque #1) : `leases.nonRecoverableChargesCents`
  (ventilation charges du bail, FEAT-036) vs `properties.condoFeesNonRecoverableCents` (charges de copro non
  récupérables du bien, rentabilité/simulateur). Un utilisateur — ou un futur dev — pourrait les croire
  redondants ou vouloir les synchroniser. **Mitigation** : libellés UI distincts et explicites, commentaires de
  code dédiés, mention dans `state/SCHEMA.md`. Ne PAS tenter de les fusionner en V1 (usages et niveaux d'entité
  différents). *À surface au PO.*
- **Malentendu produit sur « total vs récupérable »** (risque #2) : si le PO/utilisateur attendait que
  `chargesAmountCents` reste le **total** (récupérable + non-récupérable) et que la régularisation en **soustraie**
  le non-récupérable, l'implémentation serait inverse. Le modèle recommandé fait de `chargesAmountCents` la
  **part récupérable** directement. **C'est la décision structurante à valider avant de coder** (voir ci-dessous).
- **Saisie utilisateur** : un bailleur qui saisissait jusqu'ici « charges = 50 € » va voir le champ relabellisé
  « Charges récupérables ». S'il y avait mis, par erreur, un montant incluant du non-récupérable, la migration
  lazy le laisse tel quel (récupérable = 50, NR = 0) — ce qui reste cohérent et non destructif ; il pourra
  corriger à l'édition. Aucun risque de perte de données.
- **Codegen** : oublier `build_runner` après modif de `lease.dart` ⇒ build cassé. **Mitigation** : lancer
  `dart run build_runner build --delete-conflicting-outputs` + `dart format` (CI fail si non formaté).

---

## Step-by-step execution order

1. **Backend** (`supabase-dev` → ici : dev Cloud Functions) : `lease_payment.ts` — `createLease` +
   `updateLease` (champ + validation) + tests vitest. Déployer les functions.
2. **Modèle Dart** : `lease.dart` (champ + getters) → `build_runner` → `dart format`.
3. **Data/App layer** : `lease_repository.dart` (interface + create/update) + `lease_form_controller.dart`
   (param propagé).
4. **UI** (`flutter-dev`) : `lease_form.dart` (2ᵉ champ) + `lease_form_page.dart` (ctrl + submit) +
   `lease_detail_page.dart` (ventilation).
5. **Doc régularisation** : commentaires `charge_regularization_balance.dart` (clarifier les deux non-récupérables).
6. **Tests** (`qa-tester`) : unitaires Dart + TS + widget + non-régression régularisation, mappés AC-1..5.
   Vérifier web + mobile.
7. **State** : mettre à jour `docs/state/SCHEMA.md` (champ `leases.nonRecoverableChargesCents`, note distinction
   avec `condoFeesNonRecoverableCents`) et `FEATURES.md`.
8. **Review** : `code-reviewer` + `security-auditor` (surface RLS : confirmer aucune ouverture).
9. Déploiement Firebase Hosting (avec confirmation utilisateur).

---

## ❓ Décisions à trancher avant implémentation

1. **Sémantique de `chargesAmountCents` : part récupérable (recommandé) vs total.**
   **Recommandation : `chargesAmountCents` = récupérable**, `nonRecoverableChargesCents` ajouté à côté, total
   dérivé. Zéro migration, zéro réécriture des lectures, régularisation conforme par construction. *L'alternative
   (garder `chargesAmountCents` = total et soustraire le NR à la régularisation) impose une contrainte d'égalité
   backend, une migration de tous les baux, et la réécriture de ~15 points de lecture — écartée.*

2. **Forme du modèle : deux champs plats (recommandé) vs sous-map `charges:{recoverable,nonRecoverable}`.**
   **Recommandation : deux champs plats.** Cohérent avec les autres montants du bail, rétrocompat native, pas de
   sous-modèle freezed imbriqué ni de friction avec `firestoreDocToSnakeJson`.

3. **Stratégie de migration : lazy (recommandé) vs script one-shot Admin SDK.**
   **Recommandation : lazy** (défaut `0` via freezed, `chargesAmountCents` déjà présent = récupérable). Aucun
   backfill. Script reporté à un éventuel besoin de reporting agrégé sur le non-récupérable.

4. **« Loyer CC » (`totalAmountCents`) doit-il inclure le non-récupérable ?**
   **Recommandation : NON** — `totalAmountCents` reste `loyer + récupérable` (= montant réellement dû par le
   locataire). Le non-récupérable n'est jamais facturé (décret 87-713). Le total charges R+NR n'est affiché
   qu'à titre informatif sur la fiche. *Inclure le NR fausserait cards, bandeau et quittance.*

5. **Afficher la ventilation récupérable/non-récupérable sur la quittance PDF ?**
   **Recommandation : NON en V1.** La quittance atteste ce que le locataire a payé (loyer + provisions
   récupérables). Y faire figurer le non-récupérable prêterait à confusion (le locataire pourrait croire le
   devoir) et n'a pas de fondement légal sur une quittance mensuelle. La ventilation vit sur la **fiche bail**
   (interne bailleur) et, à terme, sur l'avis de régularisation. *Réévaluable si le PO veut une quittance
   « pédagogique ».*

6. **Afficher systématiquement « Charges non récupérables » sur la fiche même à 0 ?**
   **Recommandation : OUI** — afficher les deux lignes en permanence lève l'ambiguïté (AC-4 « voit la
   ventilation ») et évite qu'un 0 masqué soit interprété comme « donnée manquante ». Coût nul.

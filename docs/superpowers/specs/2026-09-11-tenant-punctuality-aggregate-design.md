# Fiche locataire — ponctualité de paiement agrégée (factuel, par locataire)

> Spec de conception — 2026-09-11
> Statut : validée par le propriétaire (design approuvé), prête pour le plan
> d'implémentation.
> Suite différée de la spec #175 (indicateur de ponctualité **par bail**) : ici
> l'agrégation **par locataire**, explicitement reportée à l'époque.

## 1. Contexte et problème

La PR #175 a livré un indicateur **factuel** de ponctualité de paiement **par
bail** (en tête de la section Paiements de la fiche bail), en remplacement de
l'idée risquée de « noter les locataires ». Elle a posé des garde-fous légaux
stricts et a **différé** l'agrégation par locataire.

On la livre maintenant : sur la **fiche locataire**, agréger la ponctualité des
paiements enregistrés sur **l'ensemble des baux de ce locataire**, et rappeler la
ponctualité **par bail** sur chaque ligne de la section « Baux ».

**Distinction légale essentielle** : « par locataire » désigne ici le **propre
historique factuel d'un locataire** (multi-baux), agrégé pour le bailleur. Ce
n'est **pas** un comparatif, un classement ou une liste noire **entre**
locataires — cette agrégation inter-locataires reste formellement interdite (cf.
garde-fous #175, risque RGPD/profilage/discrimination).

## 2. Objectif

Afficher, sur la fiche locataire :
- **(a) un indicateur agrégé** en tête : « X/Y à l'heure · N en retard · % » sur
  tous les baux du locataire ;
- **(b) la ponctualité par bail** (indicateur #175, tel quel) sur chaque ligne de
  la section « Baux ».

De façon **responsive**, **factuelle**, **privée**, sans jamais produire de score.

## 3. État actuel (référence)

- `tenant_detail_page.dart` : charge le locataire via `tenantDetailProvider(id)`
  et ses baux **impérativement** (`TenantRepository.listLeasesForTenant(tenantId)`,
  stockés dans le state d'une section `StatefulWidget`, pas un provider). La
  projection retournée (`tenant_repository.dart` ~lignes 319-330) contient :
  `id`, `property_id`, `start_date`, `end_date`, `status`, `rent_amount_cents`
  — **pas `payment_day`**, pas les paiements.
- `TenantLeaseSummary` (widget `StatelessWidget`) affiche ces baux en liste de
  cards ; chaque `_LeaseItem` reçoit un `Map<String, dynamic>`.
- Paiements : **par bail** via `leasePaymentsProvider(leaseId)`
  (`FamilyAsyncNotifier<List<Payment>, String>`).
- Helpers réutilisables (#175) : `PaymentPunctuality {total, onTime}` (getters
  `late`, `hasPayments`, `onTimePercent` — `null` si `total < 3`) et
  `computePaymentPunctuality(payments, {paymentDay, graceDays})`
  (`lib/features/payments/domain/payment_punctuality.dart`) ; widget
  `PaymentPunctualityIndicator({leaseId, paymentDay})`
  (`lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart`).
- `leaseDueDate({paymentDay, year, month})` et `kDefaultLeaseGraceDays = 5`
  (`lib/features/leases/domain/lease_lateness.dart`).

## 4. Décisions (2026-09-11)

| Point | Décision |
|---|---|
| Emplacement | **Les deux** : agrégat en tête de la fiche locataire **+** ponctualité par bail (#175) sur chaque ligne de la section « Baux ». |
| Périmètre d'agrégation | Tous les baux **de ce locataire** (multi-baux). Somme des paiements enregistrés. **Jamais** d'agrégation/classement inter-locataires. |
| Calcul | Réutilise `computePaymentPunctuality` par bail (avec le `paymentDay` du bail), puis **somme** `total` et `onTime` en un `PaymentPunctuality` combiné. |
| Définition « à l'heure » | Inchangée : `paidAt ≤ échéance + kDefaultLeaseGraceDays` (5 j), échéance = `leaseDueDate(paymentDay, année, mois de periodStart)`. |
| Pourcentage | Affiché seulement si `total ≥ 3` (agrégé), via `PaymentPunctuality.onTimePercent`. |
| Affichage agrégat | **Même** rendu responsive que #175 : ligne complète (≥600) / pill compact (<600) + feuille de détail au tap. |
| Feuille agrégat | Identique à #175 (à l'heure X/Y · en retard N · note de méthode · note de confidentialité). **Pas** de ventilation par bail (les lignes la portent déjà). |
| Par bail | Injecter `PaymentPunctualityIndicator(leaseId, paymentDay)` (#175, inchangé) dans chaque `_LeaseItem`. |
| Source `paymentDay` | **Étendre** la projection de `listLeasesForTenant` pour inclure `payment_day` (depuis `raw['paymentDay']`). Nécessaire aux deux placements. |
| Données | Réutilise `leasePaymentsProvider` (aucun accès Firestore direct). Ajoute **N lectures** de paiements sur la fiche locataire (N = nb de baux du locataire) — la fiche ne les chargeait pas auparavant. Acceptable ; **jamais persisté** (aucune donnée « score » stockée). |
| États dégénérés | 0 bail → aucun indicateur. Paiements en cours de chargement → rien (pas de valeur partielle trompeuse). `total == 0` → rien (`hasPayments == false`), comme #175. |
| Garde-fous légaux | Factuel ; **propre historique du locataire** ; privé au bailleur ; **jamais** score/lettre/étoiles ; **aucune** agrégation/classement/liste noire inter-locataires ; jamais partagé/exporté comme « score ». |

**Écarté / différé** : comparatif ou classement entre locataires ; export ; note
qualitative ; délai moyen de retard ; couverture (mois payés / attendus).

## 5. Composants

### 5.1 Repository — `listLeasesForTenant`
Ajouter `'payment_day': raw['paymentDay'],` à la projection retournée
(`tenant_repository.dart`). Mettre à jour tout fake/mock de test qui reconstruit
cette projection.

### 5.2 Helper de combinaison (pur, testable)
Un helper pur qui combine plusieurs `PaymentPunctuality` en un seul :
```
PaymentPunctuality combinePaymentPunctuality(Iterable<PaymentPunctuality> parts)
  → total = Σ total, onTime = Σ onTime.
```
(Placé à côté de `computePaymentPunctuality`.) L'agrégat consomme ce helper après
avoir calculé la ponctualité par bail.

### 5.3 Widget agrégat — `TenantPunctualityIndicator` (ConsumerWidget)
- Entrée : la liste des baux du locataire réduite à `{leaseId, paymentDay}`
  (dérivée des maps de `listLeasesForTenant`, en ignorant les baux sans
  `payment_day`).
- Pour chaque bail : `ref.watch(leasePaymentsProvider(leaseId))` ; si un bail est
  encore en `loading`, l'indicateur ne s'affiche pas encore (rien). Une fois tous
  résolus : `computePaymentPunctuality(payments, paymentDay: paymentDay)` par
  bail, puis `combinePaymentPunctuality(...)`.
- `!hasPayments` → `SizedBox.shrink()`.
- Rendu **identique** à #175 (ligne/pill + `showModalBottomSheet`), réutilisant
  les mêmes jetons, clés i18n (`paymentsPunctuality*`) et structure de feuille.
  Extraire de `PaymentPunctualityIndicator` la partie « présentation d'un
  `PaymentPunctuality` » si cela évite la duplication (au jugement de
  l'implémenteur : réutiliser ou factoriser un sous-widget commun de rendu, sans
  réécrire la logique).
- Placé en tête de `tenant_detail_page` (fiche locataire).

### 5.4 Par bail — `TenantLeaseSummary`
Dans chaque `_LeaseItem`, insérer `PaymentPunctualityIndicator(leaseId: ..., paymentDay: ...)`
(#175), avec `paymentDay` lu depuis la map (désormais présent). Si `payment_day`
est absent d'une map (bail legacy), ne pas afficher l'indicateur pour cette ligne
(pas de crash).

## 6. Contraintes

- **Accès Firestore jamais en direct** : uniquement via `leasePaymentsProvider` et
  le repository existant. Pas de nouvelle collection, pas de persistance.
- **Jetons de design uniquement** (`AppColors` via extension, `AppSpacing`) ;
  aucune couleur en dur.
- **i18n** FR + EN — réutiliser les clés `paymentsPunctuality*` de #175 ; n'ajouter
  une clé que si un libellé nouveau est réellement nécessaire (avec `@description`
  sur le gabarit EN ; le test `arb_parity_test` l'impose).
- **Responsive** via `core/ui/breakpoints.dart` (seuil 600) — même mécanisme que
  #175.
- Réutiliser les composants #175 sans réécrire la logique de calcul.

## 7. Vérification

- `combinePaymentPunctuality` : somme correcte (2 baux 2/3 + 3/3 → 5/6) ; liste
  vide → `total == 0`, `hasPayments == false` ; seuil % agrégé (< 3 total →
  `onTimePercent == null` ; ≥ 3 → arrondi correct).
- Projection : `listLeasesForTenant` renvoie `payment_day` ; fake de test mis à
  jour.
- Widget agrégat : plusieurs baux → ligne complète (≥600) ; pill (<600) sans % si
  < 3 ; tap → feuille ; 0 paiement (tous baux vides) → rien ; un bail en loading →
  rien tant que non résolu.
- Par bail : chaque ligne de `TenantLeaseSummary` porte l'indicateur #175 ; bail
  sans `payment_day` → pas d'indicateur, pas de crash.
- `flutter analyze` clean ; suite complète verte.

## 8. Hors périmètre

- Comparatif / classement / liste noire **entre** locataires (interdit).
- Tout **partage / export** de l'indicateur ; note qualitative, lettre, étoiles.
- Couverture (mois payés / attendus) et délai moyen de retard.
- Paramétrage du délai de grâce (reste 5 j).
- Conversion de la section « Baux liés » en provider Riverpod (reste chargée
  impérativement — hors périmètre).

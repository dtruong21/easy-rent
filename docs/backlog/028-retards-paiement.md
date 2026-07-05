# [FEAT-028] Détection et affichage des retards de paiement

## User story
En tant que **propriétaire bailleur**, je veux **voir clairement quels baux ont un loyer impayé au titre du mois en cours (et depuis quand)** afin de **relancer les bons locataires sans avoir à recalculer moi-même les échéances**.

## Context & motivation

Le calcul actuel (`fetchRetards()` dans `lib/features/dashboard/data/dashboard_repository.dart`, lignes 86-139) est un faux-positif/faux-négatif générateur :

- **Faux négatif majeur** : un bail est ignoré tant que `startDate` n'est pas antérieure à `now − 35 jours`. Un bail qui démarre il y a 20 jours dont la 1ʳᵉ échéance est déjà dépassée et impayée est **invisible** — alors que c'est le cas le plus urgent à signaler (nouveau locataire, premier test de paiement).
- **Logique de couverture erronée** : la règle regarde uniquement la date du **dernier paiement enregistré** (`paidAt`), pas la **période qu'il couvre** (`periodStart`/`periodEnd`). Un propriétaire qui encaisse en avance (ex. paiement du 2 janvier fait le 28 décembre) ou qui a un paiement partiel verra un résultat incohérent. Le champ d'échéance du bail (`paymentDay`) n'est jamais consulté.
- **Aucun affichage au niveau bail** : le KPI dashboard `Retards de paiement` renvoie vers `/leases?filter=active` (tous les baux actifs), pas vers un filtre « en retard ». Le commentaire dans `kpi_grid.dart` (ligne 72-76) documente explicitement ce trou : *"la distinction fine (vue paiements dédiée, filtre « retard ») viendra quand LeaseListItem portera l'info paiement"*. Cette feature comble ce trou.

Sans cette correction, le KPI phare du dashboard (raison d'être : alerter sur les impayés) ment activement au propriétaire.

## Modèle de données (vérifié dans le code, 2026-07-04)

- `Lease` (`lib/features/leases/domain/lease.dart`) : `paymentDay` (int, jour du mois, défaut `1`), `rentAmountCents`, `chargesAmountCents`, `startDate`, `endDate?`, `status` (`LeaseStatus`: `active` / `terminated` / `archived` — `archived` est une valeur défensive non exposée en UI, cf. FEAT-005).
- `Payment` (`lib/features/payments/domain/payment.dart`) : `leaseId`, `periodStart`, `periodEnd`, `paidAt`, `rentAmountCents`, `chargesAmountCents`, `paymentMethod`.
- `LeaseFilter` (`lib/features/leases/domain/lease_filter.dart`) : enum `all` / `active` / `renewable` / `terminated` — pas de valeur retard actuellement.
- `leaseStatusPill()` (`lib/features/leases/presentation/widgets/lease_status_mapper.dart`) : mapping priorité descendante déjà en place (`renewable` > `active` > `terminated` > `archived`) vers un `StatusPill`. `StatusPillTone.danger` existe déjà dans `status_pill_tone.dart` (couleur rouge/oxblood, cf. `app_colors.dart`) — **pas de tone à créer**, juste à câbler.

## Règle de retard (proposition à valider — voir § Décisions)

### Définition

Un bail **actif** (`status == LeaseStatus.active`) est **en retard** si :

1. La **période due courante** — le mois calendaire dont l'échéance (`paymentDay`) est atteinte ou dépassée à la date du jour — **n'est couverte par aucun paiement enregistré** (non soft-supprimé),
2. **ET** le délai de grâce après l'échéance est dépassé.

### Calcul de la période due courante

- L'échéance du mois `M` tombe le `min(paymentDay, dernier jour de M)` (clamp pour les mois courts — ex. `paymentDay=31` en février → échéance le 28/29).
- Le mois `M` est « dû » si `today >= échéance(M)`.
- On ne calcule la période due **qu'à partir du mois de démarrage du bail** (cf. proratisation ci-dessous) — jamais avant `startDate`.

### Couverture par un paiement

Un paiement `P` couvre le mois `M` si l'intervalle `[P.periodStart, P.periodEnd]` **recouvre** le mois calendaire `M` (au moins un jour d'intersection). On agrège l'ensemble des paiements du bail : si l'union de leurs intervalles couvre entièrement `M`, le mois est considéré payé.

- **Paiement en avance** (ex. `periodStart`=1er janvier, `periodEnd`=31 janvier, `paidAt`=28 décembre) : couvre bien janvier → non en retard en janvier. Le `paidAt` ne sert **qu'à l'affichage/tri**, jamais au calcul de couverture.
- **Paiement partiel** (montant < loyer dû mais période déclarée = mois complet) : MVP — on ne vérifie **pas** le montant, seulement le recouvrement de période. Un paiement partiel dont la période couvre le mois est considéré comme "mois payé" (limite connue, voir § Out of scope).
- **Paiement multi-mois** (ex. `periodStart`=1er janvier, `periodEnd`=31 mars, un seul paiement) : couvre janvier, février et mars.

### Délai de grâce

**Proposition : 5 jours calendaires après l'échéance.**

Justification :
- 3 jours est trop court pour absorber les délais bancaires usuels (virement SEPA J+1 à J+2, week-end/jour férié autour du `paymentDay`).
- 5 jours couvre un `paymentDay` tombant un vendredi + virement lancé le jour même (arrivée mardi/mercredi suivant) sans laisser un mois entier de tolérance implicite.
- Reste strictement inférieur à l'ancien seuil de 35 jours qui masquait le problème pendant plus d'un mois.
- Le délai de grâce **ne s'applique qu'à l'affichage "en retard"**, pas à la relance métier (hors scope) — un propriétaire pressé peut toujours consulter `payments` bail par bail avant J+5.

### Cas limites

| Cas | Règle |
|---|---|
| **Bail démarrant en cours de mois** | Pas de proratisation. La 1ʳᵉ échéance due est celle du **mois calendaire suivant le mois de démarrage** (ex. bail qui démarre le 15 mars, `paymentDay=5` → 1ʳᵉ échéance le 5 avril). Le mois de démarrage lui-même n'est jamais compté comme "dû" pour la détection de retard — il est couvert par le loyer initial géré manuellement par le propriétaire (dépôt de garantie, prorata négocié) et sort du scope de cette règle automatique. **Exception** : si `paymentDay <= jour de démarrage`, l'échéance du mois de démarrage est déjà "passée" au moment de la signature — dans ce cas aussi, on saute au mois suivant (évite un faux "en retard" dès J+5 après signature). |
| **Paiement partiel** | Non détecté par le MVP (recouvrement de période uniquement, pas de vérification de montant) — documenté comme limite connue. |
| **Bail terminé (`status == terminated`)** | Jamais en retard, quelle que soit l'historique de paiement. Un bail `archived` (valeur défensive, non exposée UI) suit la même règle que `terminated` : jamais en retard. |
| **Paiement en avance couvrant plusieurs mois** | Couvre tous les mois inclus dans `[periodStart, periodEnd]` — aucun de ces mois n'est en retard. |
| **Bail sans aucun paiement, très récent (< délai de grâce)** | Non en retard tant que le délai de grâce n'est pas écoulé pour la 1ʳᵉ échéance due. |
| **Bail sans aucun paiement, 1ʳᵉ échéance dépassée de plus du délai de grâce** | En retard — **c'est le bug corrigé par cette feature** (l'ancienne règle l'ignorait car `startDate` récente). |

## Affichage

1. **KPI dashboard** (`RetardsKpi` / `kpi_grid.dart`) : le compte doit refléter le nombre de baux en retard selon la règle ci-dessus (remplace le calcul actuel de `fetchRetards()`). Le `onTap` du KPI `Retards de paiement` pointe vers `/leases?filter=late` (au lieu de `?filter=active` aujourd'hui).
2. **`LeaseFilter`** : ajout d'une valeur `late` (libellé FR : *"En retard"*), au même niveau que `active` / `renewable` / `terminated`. Disponible dans la barre de filtre de `/leases` (`leases_filter_bar.dart`) et parsable depuis le query param `?filter=late` (`LeaseFilter.fromQueryParam`).
3. **Pastille "En retard"** sur `LeaseCard` et `LeaseDetailPage` : `StatusPill` avec `tone: StatusPillTone.danger`. **Priorité d'affichage** (un bail peut être à la fois "en retard" et "à renouveler") : **`late` prime sur `renewable`** — un impayé est plus urgent qu'une échéance de renouvellement. Ordre de priorité complet dans `leaseStatusPill()` : `late` > `renewable` > `active` > `terminated` > `archived`.
4. Aucun changement sur `/leases/:id/payments` ni sur la génération de quittance — cette feature est **lecture seule** (dérivation d'un statut d'affichage), aucune mutation de `payments` ou `leases`.

## Acceptance criteria (Gherkin)

```gherkin
Fonctionnalité : Détection des retards de paiement

  Contexte :
    Étant donné un propriétaire connecté avec au moins un bien et un locataire
    Et le délai de grâce est configuré à 5 jours

  Scénario : Bail récent avec 1ʳᵉ échéance dépassée et impayée → détecté
    Étant donné un bail actif ayant démarré il y a 20 jours avec paymentDay=1
    Et le mois calendaire suivant le démarrage a déjà son échéance dépassée de plus de 5 jours
    Et aucun paiement n'existe pour ce bail
    Quand le dashboard calcule les retards
    Alors ce bail est compté dans le KPI "Retards de paiement"
    Et une pastille "En retard" (tone danger) est visible sur sa LeaseCard
    Et ce bail apparaît dans /leases?filter=late

  Scénario : Bail payé pour le mois en cours → non détecté
    Étant donné un bail actif avec paymentDay=5
    Et un paiement dont periodStart/periodEnd couvre le mois calendaire en cours
    Quand le dashboard calcule les retards
    Alors ce bail n'est PAS compté dans le KPI "Retards de paiement"
    Et aucune pastille "En retard" n'est visible sur sa LeaseCard

  Scénario : Échéance dépassée mais dans le délai de grâce → non détecté
    Étant donné un bail actif avec paymentDay=1
    Et la date du jour est le 4 du mois (3 jours après l'échéance, < 5 jours de grâce)
    Et aucun paiement ne couvre le mois en cours
    Quand le dashboard calcule les retards
    Alors ce bail n'est PAS compté dans le KPI "Retards de paiement"

  Scénario : Échéance dépassée au-delà du délai de grâce → détecté
    Étant donné un bail actif avec paymentDay=1
    Et la date du jour est le 7 du mois (6 jours après l'échéance, > 5 jours de grâce)
    Et aucun paiement ne couvre le mois en cours
    Quand le dashboard calcule les retards
    Alors ce bail EST compté dans le KPI "Retards de paiement"

  Scénario : Bail terminé → jamais en retard
    Étant donné un bail avec status="terminated" sans aucun paiement récent
    Quand le dashboard calcule les retards
    Alors ce bail n'est PAS compté dans le KPI "Retards de paiement"
    Et aucune pastille "En retard" n'apparaît, même si l'historique montre des mois non couverts

  Scénario : Paiement en avance couvrant le mois dû → non détecté
    Étant donné un bail actif avec paymentDay=1
    Et un paiement effectué le 28 du mois précédent avec periodStart/periodEnd couvrant le mois suivant en entier
    Quand le dashboard calcule les retards pour le mois suivant
    Alors ce bail n'est PAS compté dans le KPI "Retards de paiement"

  Scénario : Bail démarrant en cours de mois → pas de fausse alerte sur le mois de signature
    Étant donné un bail actif ayant démarré le 15 du mois avec paymentDay=1
    Et aucun paiement n'existe encore
    Et la date du jour est le 20 du même mois (5 jours après démarrage)
    Quand le dashboard calcule les retards
    Alors ce bail n'est PAS compté en retard (la 1ʳᵉ échéance due est le 1er du mois suivant)

  Scénario : Drill-down depuis le KPI
    Étant donné au moins un bail en retard selon la règle ci-dessus
    Quand le propriétaire clique sur le KPI "Retards de paiement" du dashboard
    Alors il est redirigé vers /leases?filter=late
    Et la liste affiche uniquement les baux en retard

  Scénario : Priorité d'affichage retard vs renouvellement
    Étant donné un bail actif en retard de paiement ET dont endDate est dans moins de 60 jours
    Quand la pastille de statut est calculée
    Alors la pastille affichée est "En retard" (tone danger), pas "À renouveler"
```

## Out of scope

- **Vérification du montant payé** (paiement partiel non détecté comme retard — seule la couverture de *période* est vérifiée, pas le *montant*). Nécessiterait de comparer `rentAmountCents + chargesAmountCents` payés vs dus par mois — traité en P2 si le besoin remonte.
- **Relances automatiques** (email, SMS) au locataire en retard — feature distincte (P1-002 "Rappels paiement" déjà notée dans `docs/state/INDEX.md`).
- **Historique / liste des mois en retard cumulés** (ex. "3 mois de retard") — le MVP de cette story détecte un état binaire "en retard sur l'échéance courante", pas un cumul multi-mois. Peut être dérivé plus tard de la même logique de couverture appliquée à chaque mois écoulé.
- **Modification du champ `paymentDay` ou de la configuration du délai de grâce par l'utilisateur** — le délai de grâce est une constante applicative, pas un paramètre par bail ou par propriétaire dans cette itération.
- **Toute modification de `firestore.rules` ou de `functions/`** — la détection reste 100% client (lecture `leases` + `payments`, déjà autorisée par les rules existantes). Contrainte dure : WIP local en cours sur ces deux zones (branche `feature/anon-auth-m1`), ne pas y toucher.
- **Backfill / recalcul batch** — pas de Cloud Function de recalcul planifié ; le statut est dérivé à la volée à chaque lecture (dashboard + liste des baux).

## Dependencies

- Collections Firestore : `leases` (lecture : `paymentDay`, `startDate`, `endDate`, `status`, `landlordId`, `deletedAt`), `payments` (lecture : `leaseId`, `periodStart`, `periodEnd`, `landlordId`, `deletedAt`) — aucune nouvelle collection, aucune écriture.
- Features bloquantes : aucune — FEAT-005 (CRUD baux, `paymentDay` déjà en base), FEAT-006 (CRUD paiements, `periodStart`/`periodEnd` déjà en base) et FEAT-010 (dashboard KPI) sont déjà livrées.
- Fichiers à modifier (repère pour l'agent d'implémentation, pas une spec technique) : `dashboard_repository.dart` (`fetchRetards`), `lease_filter.dart` (`LeaseFilter.late`), `lease_status_mapper.dart` (priorité `late`), `kpi_grid.dart` (drill-down `?filter=late`), `leases_filter_bar.dart` (nouvel onglet filtre).

## Legal / compliance notes

Aucune mention légale nouvelle requise — cette feature est un outil d'aide à la gestion, pas un document contractuel ou une quittance. Elle ne modifie ni la loi du 6 juillet 1989 (quittances) ni la conservation des données (RGPD, 5 ans) : lecture seule sur des données déjà stockées conformément aux règles existantes.

## Priority

P1 (post-MVP) — corrige un KPI du dashboard MVP existant (FEAT-010) qui est actuellement trompeur, mais n'est pas un des 10 piliers P0. À prioriser haut dans le backlog P1 vu l'impact (le KPI phare de suivi des impayés ment).

## Estimated effort

M (1-3 jours) — logique de calcul non triviale (couverture de période, clamp fin de mois, priorité d'affichage) mais périmètre fonctionnel contenu (lecture seule, pas de nouvelle collection, pas de Cloud Function).

## Decisions requiring product/user sign-off

1. **Délai de grâce** : proposition 5 jours calendaires. À valider ou ajuster (3 jours ? 7 jours ? configurable plus tard ?).
2. **Proratisation du mois de démarrage** : proposition "pas de proratisation, 1ʳᵉ échéance = mois calendaire suivant le démarrage (ou le même mois si `paymentDay` > jour de démarrage)". À valider — alternative possible : compter le mois de démarrage au prorata si `paymentDay` tombe après la date de démarrage dans le même mois.
3. **Paiement partiel** : accepté comme hors-scope MVP (seule la période compte, pas le montant) ? Ou faut-il basculer en P0 de cette story si c'est un cas fréquent en pratique ?
4. **Priorité d'affichage `late` vs `renewable`** : proposition "retard prime sur renouvellement" sur la pastille. À confirmer.

## Risks (implementation-facing, non bloquants pour la spec)

- **Index composite Firestore potentiellement manquant** : la détection nécessite de récupérer, pour chaque bail actif, les paiements dont l'intervalle `[periodStart, periodEnd]` peut chevaucher le mois dû. L'index existant `landlordId, leaseId, deletedAt, periodStart DESC` (voir `firestore.indexes.json`) permet de trier par `periodStart` mais une requête de recouvrement d'intervalle (`periodStart <= finDeMois AND periodEnd >= débutDeMois`) sur deux champs de plage n'est pas supportée nativement par Firestore (une seule inégalité par requête). Solution probable : requêter tous les paiements du bail (déjà un jeu réduit, indexé par `leaseId`) et faire le test de recouvrement côté client en Dart, comme le fait déjà `fetchRetards()` actuel pour `paidAt`. À confirmer/trancher côté architecte — ne pas ajouter d'index dans cette story.
- **Coût de lecture** : pour N baux actifs, la règle nécessite de charger l'historique de paiements de chacun (pas juste le dernier), potentiellement plus coûteux en lectures Firestore que l'heuristique actuelle. À surveiller si le portefeuille grossit (pagination/`whereIn` chunking déjà en place dans `fetchRetards()` à réutiliser).

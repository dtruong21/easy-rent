# Dashboard — panneau « À traiter / À venir » + graphe cash-flow repliable

> Spec de conception — 2026-09-08
> Statut : validée par le propriétaire, prête pour le plan d'implémentation.

## 1. Contexte et problème

Le dashboard affiche, dans l'ordre : en-tête → `KpiGrid` (4 compteurs) →
`PortfolioYieldSection` (rendement + cash-flow lissé) → **`MonthlyCashflowChart`**
(cash-flow réel mois par mois) → `RecentActivitySection`.

Le propriétaire juge le graphe cash-flow **peu utile au quotidien** : sans crédit
ni dépenses saisis, le cash-flow réel ≈ le loyer (connu d'avance) → courbe plate.
Le graphe n'est riche que pour les utilisateurs qui saisissent crédit + dépenses ;
pour les autres il occupe le meilleur emplacement sans rien apprendre.

En parallèle, les informations **actionnables** que le bailleur veut voir en un
coup d'œil (qui est en retard, quels baux finissent bientôt) existent en base
mais ne sont exposées que comme **compteurs** dans `KpiGrid` : pour voir le
détail, il faut quitter le dashboard.

## 2. Objectif

1. Remplacer le graphe cash-flow, à son emplacement, par un **panneau
   actionnable** « À traiter / À venir » qui montre le **détail** (pas juste des
   compteurs) : encaissements du mois, loyers en retard, baux finissant bientôt.
2. **Conserver** le graphe cash-flow, déplacé plus bas dans une carte
   **repliable, fermée par défaut** — il reste disponible pour qui saisit
   crédit + dépenses, sans encombrer.

## 3. Décisions (2026-09-08)

| Point | Décision |
|---|---|
| Contenu du panneau | Encaissements du mois **+** retards **+** baux finissant. Régularisations de charges **différées** (v2 — pas de signal calculé aujourd'hui). |
| Source de données | **Réutilise l'existant, zéro nouvelle requête Firestore** : `LoyersMoisKpi` (déjà dans le snapshot dashboard) pour les encaissements ; `leasesListProvider` (même source que l'écran Baux) pour retards + baux finissant. |
| Cohérence avec l'écran Baux | Le panneau dérive retards/finissant avec **la même sémantique** que `filteredLeasesProvider` (retard = `status==active && isLate` ; finissant = `status==active && !isLate && endDate < 60 j`), pour que « Voir tout » ouvre exactement la même liste. |
| Graphe cash-flow | Déplacé sous le panneau (au-dessus de « Activité récente »), dans une carte repliable **fermée par défaut**. |
| Design | Réutilise les jetons existants (`AppColors.success/warning/danger`, `AppSpacing`, `AppRadii`) et le style de cartes du dashboard. Aucune couleur en dur. |

**Écarté / différé** : régularisations de charges dues (nouveau calcul annuel
mode provisions) ; suppression pure du graphe (le propriétaire veut le garder
repliable) ; un nouveau graphe attendu-vs-encaissé (reste plat si tout est payé,
rétrospectif, ne couvre pas les échéances).

## 4. Structure du panneau « À traiter / À venir »

Une carte (même enveloppe que les autres sections dashboard) contenant :

### 4.1 Bandeau encaissements du mois
- « **X € encaissé** / Y € attendu » (à partir de `LoyersMoisKpi.encaissedCents`
  et `dueCents`).
- **Reste dû** = `max(0, dueCents − encaissedCents)`, en ton `warning` si > 0,
  `success` (ou neutre) si = 0.
- Petite **barre de progression** encaissé/attendu (clampée 0–100 %). Si
  `dueCents == 0` (aucun bail actif), afficher un état neutre sans barre.

### 4.2 Liste actionnable
Lignes, chacune cliquable vers l'écran concerné. Ordre : retards d'abord, puis
baux finissant.

- **Loyer en retard** (`item.isLate`, bail actif) :
  - locataire (`tenantDisplayName`) · bien (`propertyName`) · montant du loyer
    du bail · badge **« en retard »** (ton `danger`).
  - tap → `context.go('/leases?filter=late')`.
  - (Optionnel, si dispo à faible coût via `lease_lateness`) nombre de jours de
    retard ; sinon on n'affiche que le badge — non bloquant.
- **Bail finissant** (`status==active && !isLate && endDate < 60 j`) :
  - bien (`propertyName`) · locataire (`tenantDisplayName`) · **date de fin**
    (`lease.endDate`, format français), ton `warning`.
  - tap → `context.go('/leases?filter=renewable')`.

**Limite d'affichage** : au plus **3 lignes par catégorie** dans le panneau ;
au-delà, une ligne « + N autres » cliquable vers la liste filtrée. Garde le
panneau compact.

### 4.3 État vide
Si aucun retard **et** aucun bail finissant : un état « **Tout est à jour ✓** »
(ton `success`, discret) — le bandeau encaissements reste affiché au-dessus.

### 4.4 États loading / erreur
- Tant que `leasesListProvider` charge : squelette/loader compact cohérent avec
  les autres cartes.
- En erreur de `leasesListProvider` : le bandeau encaissements (qui vient d'une
  autre source) reste affiché ; la liste montre un message discret « détail
  indisponible » plutôt que de casser le dashboard.

## 5. Dérivation des données (couche application)

Un provider dédié (ex. `dashboardActionItemsProvider`) qui `watch`
`leasesListProvider` et retourne deux listes dérivées :
- `late` : `items.where((i) => i.lease.status == active && i.isLate)`.
- `ending` : `items.where((i) => i.lease.status == active && !i.isLate &&
  i.lease.endDate != null && i.lease.endDate!.difference(now).inDays < 60)`.

La logique `_isRenewable` (< 60 j) existe déjà en privé dans
`leases_filter_provider.dart` : **l'extraire en helper partagé** (p. ex.
`lib/features/leases/domain/lease_renewal.dart` : `bool isLeaseRenewable(Lease,
DateTime now)`) et l'utiliser des deux côtés, pour ne pas dupliquer le seuil.

Le bandeau encaissements lit `snapshot.loyers` (`LoyersMoisKpi`), déjà présent
dans `DashboardSnapshot`.

## 6. Graphe cash-flow repliable

- `MonthlyCashflowChart` déplacé **sous** le panneau, **au-dessus** de
  « Activité récente ».
- Enveloppé dans une carte **repliable** (type `ExpansionTile` ou équivalent
  maison cohérent avec le design), **fermée par défaut**, titre explicite
  « **Cash-flow mensuel — détail** » + court sous-titre rappelant qu'il est
  pertinent surtout avec crédit/dépenses saisis.
- Le composant `MonthlyCashflowChart` **n'est pas réécrit** — seulement
  enveloppé. Ses providers (`monthlyCashflowProvider`, période, format) et son
  chargement séparé restent inchangés. Idéalement, le contenu n'est construit
  qu'une fois déplié (lazy) pour ne pas déclencher `monthlyCashflowProvider`
  tant que la carte est fermée.
- **Persistance de l'état replié** : hors périmètre v1 (repli par défaut à
  chaque ouverture du dashboard suffit) ; réutiliser un provider de préférence
  si trivial, sinon différer.

## 7. Contraintes

- **Zéro nouvelle requête Firestore** : réutilise `leasesListProvider` et
  `LoyersMoisKpi`. Respecte le garde-fou d'isolation (accès Firestore jamais en
  direct) — mais aucun nouvel accès n'est ajouté de toute façon.
- **Jetons** uniquement (`AppColors.success/warning/danger` via l'extension,
  `AppSpacing`, `AppRadii`) ; aucune couleur en dur.
- **Responsive** : le panneau passe proprement en une colonne sur mobile ; les
  lignes tronquent (ellipsis) plutôt que déborder.
- **i18n** : tous les libellés via `AppLocalizations` (FR + EN), comme le reste
  du dashboard.
- **Navigation** : réutilise les routes/filtres existants
  (`/leases?filter=late`, `/leases?filter=renewable`).

## 8. Vérification

- Panneau avec retards → lignes correctes (locataire/bien/montant/badge), tap →
  `/leases?filter=late`.
- Panneau avec baux finissant < 60 j → lignes correctes, tap →
  `/leases?filter=renewable`.
- Aucun retard ni bail finissant → état « Tout est à jour ✓ », bandeau toujours
  visible.
- Bandeau : reste dû = `max(0, dû − encaissé)`, barre clampée, cas `dueCents==0`
  géré.
- Cohérence : les items du panneau == les items de l'écran Baux pour le même
  filtre (même helper `isLeaseRenewable`).
- Le graphe est présent, replié par défaut, et se déplie sans régression.
- `flutter analyze` clean, suite de tests verte (widget tests du panneau +
  dérivation).

## 9. Hors périmètre

- Régularisations de charges dues (v2 — nouveau calcul).
- Compteur exact de jours de retard si non exposé à faible coût.
- Persistance de l'état replié du graphe.
- Toute modification du calcul du cash-flow lui-même.

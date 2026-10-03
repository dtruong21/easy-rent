# Dashboard — KPI patrimoniaux (occupation, patrimoine) + dé-duplication

> Spec de conception — 2026-09-09
> Statut : validée par le propriétaire, prête pour le plan d'implémentation.
> Suite de PR #171 (panneau « À traiter / À venir »).

## 1. Contexte et problème

Depuis PR #171, le dashboard affiche un panneau actionnable « À traiter / À
venir » (encaissements du mois, loyers en retard, baux finissant). Or la grille
KPI juste au-dessus affiche encore quatre compteurs dont **trois font désormais
doublon** avec ce panneau :

| KPI actuel | Doublon avec |
|---|---|
| Loyers du mois (€ encaissé) | bandeau encaissé/attendu du panneau |
| Retards (compteur) | liste « loyers en retard » du panneau |
| Baux à renouveler (compteur) | liste « baux finissant » du panneau |
| Documents en attente (compteur) | — (unique) |

Le propriétaire veut une grille KPI **sans redondance et plus intéressante** :
des métriques **patrimoniales** que le dashboard ne montre nulle part.

## 2. Objectif

Remplacer la grille KPI par trois cartes non redondantes :
1. **Taux d'occupation** — biens loués / total.
2. **Patrimoine** — somme des prix d'achat renseignés.
3. **Documents en attente** — conservé tel quel (unique).

## 3. Décisions (2026-09-09)

| Point | Décision |
|---|---|
| KPI retirés | **Loyers du mois, Retards, Baux à renouveler** — redondants avec le panneau. Retards/renouvellements restent atteignables via les lignes du panneau (`/leases?filter=late|renewable`). La navigation du KPI « loyers » (`/leases?filter=active`) est abandonnée (mineur). |
| Occupation | `biens avec activeLeaseId != null / total biens`, affiché « X/Y · Z % ». |
| Patrimoine | **somme des `purchasePriceCents` renseignés** = montant **à l'achat** (factuel), pas une estimation de marché. |
| Source de données | **`propertiesListItemsProvider` seul** (déjà observé par le dashboard via `PortfolioYieldSection`) — `PropertyListItem` porte `activeLeaseId` (occupation) et `property.purchasePriceCents` (patrimoine). **Zéro nouvelle requête Firestore.** |
| Composant | Réutilise le `KpiCard` existant (label / value / subtitle / semanticColor / onTap). |
| Fiabilité paiement locataire (« notation ») | **Hors périmètre** — spec séparée (indicateur factuel sur la fiche locataire/bail). C'est l'alternative légale à la notation ; à ne PAS traiter ici. |

**Écarté / différé** : estimation de **valeur de marché actuelle** (nécessite une
hypothèse d'appréciation → v2) ; KPI **revenu locatif mensuel** / rent roll (non
retenu par le propriétaire) ; fiabilité paiement locataire (spec B séparée).

## 4. Définition des trois KPI

### 4.1 Taux d'occupation
- **Valeur** : pourcentage `occupés / total` arrondi entier (ex. « 100 % »).
- **Sous-titre** : « X/Y loués » ; si au moins un bien vacant, mentionner
  « N vacant(s) » en ton `warning`, sinon ton neutre.
- **occupé** = `PropertyListItem.activeLeaseId != null`.
- **Aucun bien** (`total == 0`) : afficher « — » et un sous-titre neutre
  (« Aucun bien »), pas de division par zéro.
- **onTap** → `/properties`.

### 4.2 Patrimoine
- **Valeur** : `MoneyFormat.formatEurosFromCents(Σ purchasePriceCents renseignés)`.
- **Sous-titre** : « à l'achat » ; si certains biens n'ont pas de prix,
  « sur N/M biens renseignés » (N = biens avec prix, M = total).
- **Aucun prix renseigné** (N == 0) : valeur « — », sous-titre incitatif
  « Renseignez le prix d'achat » (ton neutre) — pas un « 0 € » trompeur.
- **Ton** : neutre (donnée informative, pas un état).
- **onTap** → `/properties`.

### 4.3 Documents en attente
- **Inchangé** : valeur = `docs.count`, ton `warning` si > 0, onTap actuel
  conservé. (Ne pas régresser le comportement existant.)

## 5. Disposition
- Ordre du dashboard **inchangé** ; seule la composition de `KpiGrid` change.
- La grille reste responsive (auto-fit existant) ; 3 cartes au lieu de 4.
- La section « Rentabilité portfolio » (rendement brut/net, cash-flow) juste en
  dessous reste **intacte** — occupation/patrimoine ne la recoupent pas.

## 6. Contraintes

- **Zéro nouvelle requête Firestore** : dérive `propertiesListItemsProvider`
  (déjà chargé). Aucun accès Firestore direct.
- **Jetons uniquement** (`AppColors` via l'extension pour le ton `warning`,
  `AppSpacing`) ; aucune couleur en dur.
- **i18n** FR + EN pour tous les nouveaux libellés/sous-titres.
- Réutilise `KpiCard` et le style existant de `KpiGrid` ; ne réécrit pas la
  grille.
- Les tests existants de `KpiGrid` référençant `kpi_retards` /
  `kpi_renouvellements` / `kpi_loyers` seront mis à jour (ces cartes
  disparaissent) ; ajouter des tests pour `kpi_occupation` et `kpi_patrimoine`.

## 7. Vérification
- Grille : 3 cartes `kpi_occupation`, `kpi_patrimoine`, `kpi_docs` ; plus de
  `kpi_retards` / `kpi_renouvellements` / `kpi_loyers`.
- Occupation : 2/2 loués → « 100 % · 2/2 loués » ; 1/2 → « 50 % · 1/2 loués ·
  1 vacant » (ton warning) ; 0 bien → « — · Aucun bien ».
- Patrimoine : 2 biens à 118 000 € + 118 000 € → « 236 000 € · à l'achat » ;
  1 des 2 sans prix → « 118 000 € · sur 1/2 biens renseignés » ; aucun prix →
  « — · Renseignez le prix d'achat ».
- Docs en attente : comportement identique à aujourd'hui.
- onTap occupation/patrimoine → `/properties`.
- `flutter analyze` clean, suite verte.

## 8. Hors périmètre
- **B — Fiabilité de paiement locataire** (spec séparée ; alternative légale à
  la notation, sur la fiche locataire/bail).
- Estimation de **valeur de marché actuelle** (v2, hypothèse d'appréciation).
- KPI **revenu locatif mensuel** (non retenu).
- Toute modification du panneau « À traiter / À venir » ou de la section
  Rentabilité portfolio.

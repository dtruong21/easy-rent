# Cartes de liste « chiffre clé » + puces de filtre — design

> Date : 2026-09-29 · Statut : validé (brainstorming) · Portée : client Flutter uniquement
> Origine : recette mobile iOS du 2026-09-28 — « trop d'espace non utilisé,
> design pas optimisé ». Le correctif technique de hauteur (#195) est déjà livré ;
> ce spec traite la densité, la hiérarchie de l'information et les actions.

## 1. Problème

Les 4 listes principales (biens, baux, locataires, quittances) utilisent
`EntityCard` : un en-tête (pastille, nom, adresse, statut), **trois lignes à
icône** (type, locataire, loyer — « — » quand vide) puis **deux boutons contour**
en pied de carte. Sur mobile :

- ~150 px par carte pour 4 informations utiles ; les boutons occupent ~1/3 de
  la hauteur alors que le tap sur la carte ouvre déjà la fiche ;
- le chiffre qui intéresse le bailleur (loyer / montant) est noyé dans une
  ligne grise ;
- le filtre (« Tous ▾ ») occupe une ligne entière et cache ses options.

## 2. Décisions (validées)

| # | Décision | Choix |
|---|---|---|
| D1 | Périmètre | Les 4 listes (cartes + en-tête de liste). Accueil = passe ultérieure. |
| D2 | Actions | **1 action rapide visible** par carte + **menu ⋮** pour le reste. Tap carte = fiche (quittance : ouvre le PDF). |
| D3 | Forme de carte | **C — « chiffre clé »** : liseré gauche couleur du bien, titre/sous-titre à gauche, montant en gros à droite, ligne basse pastille de statut + info + action rapide. |
| D4 | Filtre | **Puces horizontales avec compteurs** (`Tous 3 · Avec bail 2 · Sans bail 1`), défilement horizontal si trop large. |
| D5 | Plateformes | **Partout** : même carte et mêmes puces sur mobile, tablette et desktop. La vue tableau desktop (`ViewMode.table`) ne change pas. |

Maquettes de référence : `.superpowers/brainstorm/*/content/four-types.html`
(non versionné).

## 3. Anatomie de la carte (`SummaryCard`)

```
┌▌───────────────────────────────────────────────┐
│▌ Titre (600, 1 ligne, ellipsis)      800 €   ⋮ │   ← chiffre clé (17 px, 700)
│▌ Sous-titre (muted, 1 ligne)        CC / mois  │   ← légende (11 px, muted)
│▌ [Pastille]  info (muted, 1 ligne)  [Action]   │
└▌───────────────────────────────────────────────┘
```

- **Liseré gauche** 4 px, couleur d'identité du bien (`PropertyColorKey`) ;
  gris neutre (`outlineVariant`) quand aucune couleur (locataire sans bail).
  Remplace la pastille ronde et le fond teinté actuels.
- **Chiffre clé** optionnel (valeur + légende). Absent → l'action rapide prend
  sa place en haut à droite (cas « Vacant », « Sans bail »).
- **Action rapide** optionnelle : bouton contour compact (icône + libellé,
  hauteur ≥ 40 px, cible tactile ≥ 48 px). Une seule par carte.
- **Menu ⋮** : `PopupMenuButton`, tooltip « Plus d'actions », items avec
  option « destructive » (texte `error`).
- Padding 12 px, écart 6 px entre les deux blocs. Hauteur visée ≈ 90 px
  (contre ~150 px).
- Accessibilité : `Semantics(button: true, label: …)` sur la carte (reprend
  les `semanticLabel` existants), l'action rapide et le ⋮ restent des cibles
  séparées.

## 4. Correspondance par type

| Type / état | Titre | Sous-titre | Chiffre clé | Pastille · info | Action rapide | Menu ⋮ |
|---|---|---|---|---|---|---|
| Bien loué | nom | locataire courant | loyer CC · « CC / mois » | Loué · adresse, type, surface | — | Voir le bail · Modifier |
| Bien vacant | nom | « Aucun locataire » | — | Vacant · adresse, type | + Créer un bail | Modifier |
| Bail | nom du bien | locataire | loyer CC · « CC / mois » | statut (Actif / En retard / À renouveler / Terminé) · « depuis le JJ/MM/AAAA » | + Paiement | Quittances · Régulariser les charges (si éligible, existant) · Modifier |
| Locataire avec bail | nom complet | bien occupé | loyer CC · « CC / mois » | Bail actif · « depuis le … » | ✆ Appeler si téléphone, sinon ✉ Envoyer un email | Voir le bail · Envoyer un email (si pas en action rapide) · Modifier |
| Locataire sans bail | nom complet | email | — | Sans bail | + Créer un bail | Envoyer un email · Modifier |
| Quittance | période (« Septembre 2026 ») | bien · locataire | total · « loyer + charges » | statut (Payée / Envoyée / Annulée / Périmée) · date | ↗ Envoyer (réutilise la logique de `ShareReceiptButton`, états désactivés compris) | Ouvrir le PDF · Annuler la quittance (destructive, masqué si déjà annulée) |

- **Appeler** : `url_launcher` `tel:` ; **email** : `mailto:`. Affichés
  seulement si la donnée existe.
- Les actions de menu reprennent les destinations et callbacks actuels des
  pieds de carte (`CardActionButton`) et du menu bail existant
  (`_LeaseCardMenuAction.regularizeCharges`) — aucune nouvelle logique
  métier.

## 5. En-tête de liste (`FilterChipsBar`)

- Rangée de `ChoiceChip` à défilement horizontal, puce active pleine
  (couleur `primary`), compteur après le libellé (opacité réduite).
- Filtres existants, inchangés : biens (Tous / Loués / Vacants), baux (Tous /
  Actifs / À renouveler / En retard / Terminés), locataires (Tous / Avec bail /
  Sans bail), quittances (Toutes / Envoyées / Payées / Annulées).
- **Compteurs** : dérivés côté client de la liste non filtrée déjà chargée
  (nouveaux providers `…FilterCountsProvider`, `Map<Filter, int>`). Pas de
  requête supplémentaire. Pendant le chargement : puces sans compteur.
- Quittances : le filtre d'**année** existant reste, en dernière puce
  déroulante (« 2026 ▾ ») au bout de la rangée.
- Desktop : les puces remplacent le `SegmentedButton` ; le `ViewModeToggle`
  reste à droite de la rangée.
- Le FAB « Ajouter … » ne change pas (hors périmètre).

## 6. Architecture

Nouvelles briques partagées (`lib/core/ui/`) :

1. `cards/summary_card.dart` — `SummaryCard` (layout §3) + petits types de
   données : `SummaryKeyFigure {value, caption}`, `SummaryQuickAction {icon,
   label, onPressed?, tooltip?}` (`onPressed == null` → désactivé),
   `SummaryMenuItem {label, onSelected, destructive}`. Aucun import de
   feature : pure présentation.
2. `filters/filter_chips_bar.dart` — `FilterChipsBar<T>` : `options:
   List<FilterChipOption<T>> {value, label, count?}`, `selected`,
   `onSelected`, `trailing` optionnel.

Côté features, les cartes deviennent de **fins adaptateurs** « entité →
`SummaryCard` » :

- `PropertyCard`, `LeaseCard`, `TenantCard`, `ReceiptCard` : réécrits sur
  `SummaryCard` ; leurs widgets de pied privés (`_…CardFooter`) disparaissent.
- Filter bars (`properties_/leases_/tenants_/receipts_filter_bar.dart`) :
  réécrites sur `FilterChipsBar` + providers de compteurs.
- **Quittances mobile** : la vue timeline (`ReceiptsTimelineView`, forcée sur
  mobile) garde ses en-têtes d'année mais chaque élément devient une
  `SummaryCard` ; la colonne de marqueurs (point + trait) est supprimée
  (~40 px de largeur récupérés).
- `CardGrid` (grille ≥ 2 colonnes) : `mainAxisExtent` des 4 vues cartes
  recalibré sur la hauteur de `SummaryCard` ; `CardSkeleton` aligné.
- `EntityCard` reste (encore utilisé par `saved_scenarios_row`).
- Android : ajouter l'intent `DIAL`/`tel` dans `<queries>` du manifeste
  (`mailto` y est déjà).
- l10n FR + EN : nouvelles clés pour « Plus d'actions », « Appeler »,
  « Envoyer un email », « depuis le {date} », « CC / mois », « loyer +
  charges » ; réutiliser les clés existantes (`tenantsViewLeaseButton`,
  `tenantsCreateLeaseButton`, `propertiesNoTenant`, `commonEdit`,
  `leasesRegularizeChargesMenuItem`, `receiptsShareMenuItem`,
  `receiptsVoidMenuItem`…).

## 7. Tests

- `SummaryCard` : rendu avec/sans chiffre clé, action rapide désactivée,
  items de menu (destructive), tap carte vs tap action vs tap ⋮ isolés,
  aucune exception de débordement à 320 px avec titres longs.
- `FilterChipsBar` : compteurs affichés, sélection → callback, défilement à
  320 px sans débordement.
- Chaque adaptateur : bonne action rapide selon l'état (bien loué/vacant,
  locataire avec/sans téléphone/bail, quittance annulée), bons items de menu,
  navigation (routes existantes).
- Providers de compteurs : comptes corrects par filtre.
- Tests existants référençant les boutons de pied (`CardActionButton`, clés de
  pied) : mis à jour vers l'action rapide / le menu — **mêmes destinations**.
- Vérification manuelle : simulateur iOS (listes compactes, ⋮, Appeler,
  puces) + web desktop (grille et puces).

## 8. Hors périmètre

- Accueil / tableau de bord (passe design suivante).
- FAB, snackbars, formulaires, fiches détail (défauts mineurs suivis dans
  l'issue #197).
- Glisser pour agir (swipe) sur les cartes.
- Vue tableau desktop.

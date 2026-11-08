# Fiche bail — indicateur de ponctualité de paiement (factuel, responsive)

> Spec de conception — 2026-09-09
> Statut : validée par le propriétaire (maquette desktop + mobile approuvée),
> prête pour le plan d'implémentation.
> C'est la « spec B » différée lors du panneau dashboard : l'**alternative
> légale** à la notation de locataire.

## 1. Contexte et problème

Le propriétaire souhaitait « noter les locataires ». Une **note subjective**
d'une personne pose un risque RGPD (profilage) et de discrimination, surtout si
elle est partageable. On la remplace par un indicateur **purement factuel** de
ponctualité de paiement, dérivé des **propres enregistrements de paiement** du
bailleur — des faits, privés, sans jugement ni partage.

## 2. Objectif

Afficher, en tête de la section « Paiements » de la fiche bail, la ponctualité
des paiements enregistrés : combien ont été réglés **à l'heure**, combien **en
retard** — de façon **responsive** (web, mobile natif, web-mobile) et sans
allonger la page à scroller sur téléphone.

## 3. Décisions (2026-09-09)

| Point | Décision |
|---|---|
| Granularité | **Par bail** (les paiements appartiennent à un bail ; l'échéance dépend du `paymentDay` du bail). Agrégation par locataire = hors périmètre. |
| Emplacement | En-tête de la section **Paiements** de la fiche bail — **pas de rangée dédiée** (évite d'allonger le scroll mobile). |
| Ce qu'on mesure | **Ponctualité seule** : parmi les paiements enregistrés, « X/Y à l'heure » + nombre en retard. Pas de couverture, pas de note qualitative. |
| Définition « à l'heure » | `paidAt ≤ échéance + kDefaultLeaseGraceDays` (5 j), échéance = `min(paymentDay, dernier jour du mois de periodStart)` — **même définition que `lease_lateness`**. |
| Pourcentage | Affiché **seulement si total ≥ 3** paiements (évite un taux trompeur sur petit échantillon). |
| Responsive | **Large (≥600 px)** : ligne complète dans l'en-tête (« 9/12 à l'heure · 3 en retard · 75 % »). **Étroit (<600 px)** : **pill compact** dans la même rangée (« 9/12 · 3 retard » ou « 12/12 »). Breakpoint = `core/ui/breakpoints.dart`. |
| Détail au tap | Le chip/la ligne est **tappable** → petite feuille (bottom sheet / dialog) : à l'heure / en retard, rappel « à l'heure = réglé sous 5 j après l'échéance », et note **« Donnée privée, tirée de vos enregistrements. Jamais partagée. »** |
| Garde-fous légaux | Factuel uniquement ; **privé au bailleur** ; **jamais** de score/lettre/étoiles, jamais partagé/exporté comme « score », aucune agrégation inter-locataires ni liste noire ; aucune saisie subjective. |
| Données | Réutilise le provider de paiements du bail (déjà chargé par la section Paiements) + le bail (`paymentDay`). **Zéro nouvelle requête Firestore.** |

**Écarté / différé** : agrégation par locataire ; couverture (mois payés /
attendus) ; délai moyen de retard ; tout partage/export ; note qualitative,
lettre, étoiles, code couleur « bon/mauvais locataire ».

## 4. Calcul (helper pur, testable)

Extraire de `lease_lateness.dart` une **fonction d'échéance publique**
(actuellement `_dueDateFor` privée) :

```
DateTime leaseDueDate({required int paymentDay, required int year, required int month})
  → min(paymentDay, dernierJourDuMois(year, month)) de ce mois.
```

`lease_lateness` la réutilise (pas de duplication du clamp), même pattern que
l'extraction de `isLeaseRenewable`.

Puis un helper pur de ponctualité :

```
PaymentPunctuality computePaymentPunctuality(
  List<Payment> payments, { required int paymentDay, int graceDays = kDefaultLeaseGraceDays })
```

- Ignore les paiements soft-deleted (`deletedAt != null`).
- Pour chaque paiement : `due = leaseDueDate(paymentDay, periodStart.year, periodStart.month)` ;
  **à l'heure** si `!paidAt.isAfter(due.add(Duration(days: graceDays)))`.
- Retourne `PaymentPunctuality { int total; int onTime; }` avec getters
  `int get late => total - onTime;`, `bool get hasPayments => total > 0;`,
  `int? get onTimePercent => total >= 3 ? ((onTime/total)*100).round() : null;`
  (`null` sous 3 paiements → pas de %).

## 5. Affichage

### 5.1 Large (≥600 px) — ligne dans l'en-tête
- Icône + « **X/Y à l'heure** » ; si `late > 0`, « · N en retard » en ton
  `warning` ; si `onTimePercent != null`, « · Z % ».
- Ton d'icône : `success` si aucun retard, `warning` s'il y a des retards.

### 5.2 Étroit (<600 px) — pill compact
- Pill arrondi dans la même rangée que le titre « Paiements » : icône + texte
  court « X/Y » (+ « · N retard » si `late > 0`). Fond `bg-success` (aucun
  retard) ou `bg-warning` (retards). Pas de %. Reste sur la rangée (aucune
  ligne ajoutée).

### 5.3 Détail au tap (les deux tailles)
- Feuille modale : deux tuiles « À l'heure : X/Y » et « En retard : N »
  (N en ton `warning`), une phrase de méthode (« à l'heure = réglé sous 5 j
  après l'échéance ») et la note de confidentialité. Tappable au clavier
  (accessibilité).

### 5.4 État vide
- `total == 0` : « Aucun paiement enregistré » en ton neutre (`text-muted`),
  pas de pill coloré, pas de feuille.

## 6. Contraintes

- **Zéro nouvelle requête Firestore** ; accès Firestore jamais en direct
  (aucun nouvel accès de toute façon).
- **Jetons uniquement** (`AppColors.success/warning/neutral` via l'extension,
  `AppSpacing`) ; aucune couleur en dur.
- **i18n** FR + EN pour tout libellé, via `context.l10n`.
- **Responsive** via le breakpoint existant (`core/ui/breakpoints.dart`,
  seuil 600 px) — même mécanisme que le reste de l'app (web + mobile natif +
  web-mobile partagent le même code Flutter).
- Réutilise le composant de section Paiements existant sans le réécrire ;
  ajoute l'indicateur dans son en-tête.

## 7. Vérification
- Helper `computePaymentPunctuality` : 3/3 à l'heure ; 1 retard (paidAt =
  échéance + 6 j) compté en retard ; paidAt = échéance + 5 j pile → à l'heure
  (borne) ; soft-deleted ignoré ; `< 3` paiements → `onTimePercent == null` ;
  0 paiement → `hasPayments == false`.
- `leaseDueDate` : `paymentDay=31` en février → 28/29 (clamp) ; refactor de
  `lease_lateness` ne change pas son comportement (tests existants verts).
- Widget : large → ligne complète ; étroit (<600) → pill court sans %,
  reste sur la rangée ; tap → feuille de détail ; 0 paiement → texte neutre.
- `flutter analyze` clean, suite complète verte.

## 8. Hors périmètre
- Agrégation de ponctualité **par locataire** (spec ultérieure).
- **Couverture** (mois payés / attendus) et **délai moyen** de retard.
- Tout **partage / export** de l'indicateur ; toute note qualitative, lettre,
  étoiles, ou code couleur « bon/mauvais locataire ».
- Paramétrage du délai de grâce par bail (reste 5 j, comme `lease_lateness`).

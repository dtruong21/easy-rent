# Simulation fiscale LMNP dans le simulateur d'achat — design

Date : 2026-11-06 · Statut : validé par le PM (Daki) · Offre : Pro

## Objectif

Pour un projet d'achat en **location meublée longue durée** (LMNP), comparer dans
le simulateur existant les deux régimes fiscaux — **micro-BIC** et **réel** —
sur 10 ans : impôt sur le revenu, prélèvements sociaux, cash-flow après impôt,
et le régime le plus favorable.

Aide à la décision d'achat, **pas** une aide à la déclaration.

## Décisions du PM

| Sujet | Décision |
|---|---|
| Usage | Simulateur d'achat (pas les biens réels, pas la déclaration) |
| Tranche d'imposition | Choisie dans une liste (0 / 11 / 30 / 41 / 45 %), 30 % par défaut |
| Projet de loi de finances 2027 | Règles 2026 seules, dans une table datée ; mise à jour après le vote |
| Périmètre | LMNP longue durée seulement (ni LMP, ni meublé de tourisme) |
| Accès | Offre Pro ; teaser pour l'offre gratuite |

## Entrées ajoutées au scénario

| Champ (Firestore) | Type | Défaut | Rôle |
|---|---|---|---|
| `isFurnished` | bool | `false` | Active la section fiscale |
| `furnitureCents` | int ≥ 0 | 0 | Mobilier, amorti sur 7 ans |
| `tmiPercent` | int ∈ {0, 11, 30, 41, 45} | 30 | Tranche marginale d'imposition |
| `landSharePercent` | int 0–50 | 15 | Part du terrain dans le prix (non amortissable) |

Les scénarios existants n'ont pas ces champs : valeurs par défaut à la lecture
(`@Default` ; clés JSON du modèle en snake_case, `firestoreDocToSnakeJson` convertit), donc aucun scénario existant ne voit de section fiscale.

Écriture : la **création** passe par la callable `createScenario`, qui valide
chaque champ (`functions/src/callable/scenarios.ts`) → les 4 champs y sont
ajoutés, avec les mêmes bornes (redéploiement des Functions). La **mise à jour**
est directe (Rules : propriétaire + immuables) → mêmes bornes vérifiées côté
formulaire ; aucune donnée sensible.

## Règles fiscales — une seule table datée

`lib/features/simulator/domain/lmnp_tax_rules.dart`, constante `lmnpRules2026` :

| Règle | Valeur 2026 |
|---|---|
| Abattement micro-BIC (meublé longue durée) | 50 %, minimum 305 € |
| Plafond de recettes micro-BIC | 83 600 € / an |
| Prélèvements sociaux sur revenus BIC meublés | 18,6 % |
| Durée d'amortissement du bâti | 30 ans |
| Durée d'amortissement des travaux | 15 ans |
| Durée d'amortissement du mobilier | 7 ans |
| Seuil d'alerte LMP (recettes) | 23 000 € / an |
| Report du déficit (hors amortissement) | 10 ans, sur les revenus meublés |
| Report de l'amortissement non déduit | sans limite (art. 39 C CGI) |

La table porte son libellé (« Règles 2026 ») et l'UI l'affiche. Changer de loi =
ajouter une table et basculer la constante utilisée ; le calcul ne bouge pas.

⚠️ Avant implémentation : faire confirmer chaque valeur sur Légifrance / BOFiP
(les sources du cadrage étaient des blogs). Le taux de 18,6 % en particulier.

## Calcul (pur, sans I/O)

`lib/features/simulator/domain/lmnp_tax_simulation.dart` :
`LmnpTaxSimulation simulate(InvestmentScenario s, LmnpTaxRules rules)` → 10
lignes annuelles par régime + synthèse.

Recettes annuelles = loyer HC × 12 (constantes sur 10 ans : le simulateur
n'indexe pas les loyers aujourd'hui).

**Micro-BIC** (si recettes ≤ plafond, sinon régime « non disponible ») :
- abattement = max(recettes × 50 %, 305 €) ; imposable = max(recettes −
  abattement, 0) ;
- impôt = imposable × tranche ; prélèvements = imposable × 18,6 %.

**Réel**, année n :
- charges = taxe foncière + PNO + copropriété non récupérable + intérêts
  d'emprunt de l'année n (échéancier déjà calculé par le simulateur) + frais de
  notaire en année 1 ;
- résultat avant amortissement = recettes − charges − déficit reporté
  (déficits de moins de 10 ans, les plus anciens d'abord) ; s'il est négatif,
  il devient un nouveau déficit reportable et le résultat imposable vaut 0 ;
- amortissement disponible = dotation de l'année (bâti : prix × (1 − terrain) /
  30 ; travaux / 15 ; mobilier / 7, chacun tant que sa durée n'est pas
  écoulée) + amortissement reporté ;
- amortissement déduit = min(disponible, résultat avant amortissement positif) ;
  le reste est reporté sans limite ;
- imposable = résultat avant amortissement − amortissement déduit ;
- impôt et prélèvements comme au micro.

**Synthèse** : impôt + prélèvements cumulés sur 10 ans par régime, cash-flow
après impôt (cash-flow avant impôt existant − impôt − prélèvements) par an et
cumulé, régime le plus favorable = plus petit total cumulé (micro écarté s'il
n'est pas disponible).

Montants en centimes entiers ; arrondi à l'euro à l'affichage seulement.

## Avertissements

- Recettes > 23 000 € / an : « Au-delà de 23 000 € de loyers par an, le statut
  de loueur professionnel (LMP) peut s'appliquer ; il n'est pas simulé. »
- Recettes > 83 600 € : micro-BIC « non disponible ».
- Toujours : « À la revente, les amortissements déduits sont réintégrés dans la
  plus-value (loi de finances 2025). », « Calcul selon les règles 2026 ; une
  réforme de l'amortissement est en discussion pour 2027. », et la mention
  existante « indicatif, ne constitue pas un conseil financier ou fiscal ».

## Interface

- Formulaire du scénario : interrupteur « Bien meublé (LMNP) » ; s'il est actif,
  mobilier, tranche (liste), part du terrain (dépliable « Réglages avancés »).
- Résultats : nouvelle carte « Fiscalité LMNP » sous la carte de résultats si le
  bien est meublé — deux colonnes micro / réel (impôt + prélèvements année 1,
  cumul 10 ans, cash-flow après impôt), badge sur le régime favorable, tableau
  annuel dépliable, avertissements, libellé « Règles 2026 ».
- Offre gratuite : la carte s'affiche verrouillée (titre + phrase + bouton vers
  `/pro`) ; la ligne « Simulation fiscale LMNP/LMP » de la section « bientôt
  disponible » disparaît. Apps store : même règle que les autres incitations
  (`canOfferUpgrade`) — pas de bouton d'achat si l'achat intégré est coupé.
- Comparaison de scénarios : hors périmètre v1.

Accès Pro vérifié dans l'app (calcul d'affichage, pas de donnée protégée).

## Tests

- Unitaires du calcul, sur cas chiffrés à la main : micro simple ; plancher
  305 € ; plafond 83 600 € ; réel bénéficiaire ; réel où l'amortissement est
  reporté ; déficit de charges reporté puis consommé ; déficit périmé après
  10 ans ; fin de l'amortissement du mobilier en année 8 ; régime favorable.
- Table : chaque valeur 2026 figée par un test (toute modification devient un
  choix explicite).
- Widgets : section absente si non meublé ; verrouillée en gratuit ; complète en
  Pro ; chaque avertissement selon ses seuils.
- Callable `createScenario` : nouveaux champs acceptés, bornes refusées.

## Hors périmètre

LMP, meublé de tourisme, calcul de la plus-value, aide à la déclaration, calcul
de la tranche depuis les revenus, indexation des loyers, comparaison des
scénarios, biens réels du portefeuille.

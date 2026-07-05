# [FEAT-041] Dépenses — entité first-class pour l'argent qui sort

## User story

En tant que **bailleur utilisateur de Baillan**, je veux **enregistrer chaque dépense réelle liée à mon bien (avec sa catégorie et son justificatif)** afin de **disposer d'un historique fiable qui alimente automatiquement ma régularisation de charges et ma rentabilité, sans ressaisie**.

Décliné en sous-stories :

1. En tant que bailleur, je veux **enregistrer une dépense** (date, montant, nature, bien concerné, justificatif) afin de ne pas perdre trace d'un décompte syndic, d'une facture de travaux ou d'une prime d'assurance.
2. En tant que bailleur, je veux **consulter l'historique des dépenses d'un bien** (filtrable par période/catégorie) afin de retrouver rapidement un justificatif en cas de litige ou de contrôle.
3. En tant que bailleur, je veux que **la régularisation annuelle de charges se calcule automatiquement à partir des dépenses récupérables que j'ai enregistrées sur la période**, afin de ne plus ressaisir à la main le montant du décompte syndic à chaque régularisation.
4. En tant que bailleur, je veux **voir ma rentabilité calculée sur mes dépenses réelles** plutôt que sur des estimations annuelles statiques, afin d'avoir un rendement net et un cash-flow qui reflètent ce que je dépense vraiment.

## Context & motivation

Le diagnostic est déjà établi (cf. brief) : l'argent qui sort est aujourd'hui éclaté en 3 silos qui ne communiquent pas, sans aucune notion de « Dépense » :

1. **Provisions de charges** (`lease.chargesAmountCents`, FEAT-036 récupérable/non-récupérable) → pré-remplit `payment.chargesAmountCents` → sommées pour la régularisation. C'est de l'argent **encaissé**, pas dépensé.
2. **Coûts annuels estimés du bien** (`property.propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`, FEAT-017) : des **estimations statiques**, saisies une fois, jamais confrontées à la réalité, qui alimentent la rentabilité (FEAT-017) et le simulateur (FEAT-018).
3. **Dépenses réelles de régularisation** (FEAT-029) : lors de la régularisation annuelle, le bailleur **tape à la main** le montant total du décompte syndic dans un dialogue. Le PDF « Avis de régularisation » est généré mais **rien n'est persisté** — pas d'historique, pas de justificatif attaché, pas d'archivage (FEAT-033 identifié mais pas fait).

Conséquence ressentie : régularisation floue et répétitive (ressaisie à chaque fois), rentabilité qui ne reflète pas la réalité des dépenses.

FEAT-041 introduit une entité **Dépense** qui devient la source unique de vérité pour ce qui est réellement sorti de la poche du bailleur, et qui **absorbe FEAT-033** (l'archivage de la régularisation devient un sous-produit naturel de l'archivage des dépenses qui la composent, plutôt qu'un objet séparé à construire).

**Portée de ce document : cadrage produit uniquement.** Aucune ligne de code, migration, règle Firestore ou Cloud Function n'est proposée ici — le "comment" revient à l'architecte.

## Modèle conceptuel (WHAT, pas HOW)

### Attributs d'une Dépense

| Attribut | Description | Obligatoire |
|---|---|---|
| Date de la dépense | Date de la facture/du décompte (pas forcément la date de saisie) | Oui |
| Montant | Montant TTC de la dépense | Oui |
| Bien concerné | Le bien immobilier auquel la dépense se rattache | Oui |
| Bail concerné | Optionnel — pertinent quand la dépense est directement imputable à une période louée à un locataire donné (ex. réparation demandée par le locataire en cours de bail) | Non |
| Catégorie | **Récupérable** / **Non-récupérable** — au sens du décret n°87-713 (cf. Légal) | Oui |
| Nature | Type de dépense : syndic/charges copropriété, taxe foncière, assurance (PNO/GLI), travaux, réparation/entretien, gestion locative, autre — liste à valeur fermée (cf. Décision) | Oui |
| Période de rattachement | Période (ex. année civile ou exercice de copropriété) à laquelle la dépense se rapporte, pour l'agrégation en régularisation — distincte de la date de facture (une facture de décembre peut concerner l'exercice N+1) | Oui (pour les dépenses récupérables) |
| Justificatif | Pièce jointe (facture, décompte syndic, avis d'imposition) via le système `documents` existant | Recommandé, obligatoire si la dépense doit servir de preuve en régularisation (cf. Légal) |
| Notes / libellé libre | Description complémentaire | Non |

### Catégorie récupérable / non-récupérable (décret n°87-713 du 26 août 1987)

Le décret fixe une **liste limitative** des charges récupérables auprès du locataire. Exemples de natures **récupérables** : entretien des parties communes, ascenseur (entretien, pas grosses réparations), eau, taxe d'enlèvement des ordures ménagères, chauffage collectif, espaces verts. Exemples de natures **non-récupérables** : grosses réparations (art. 606 Code civil), taxe foncière, prime d'assurance PNO du bailleur, honoraires de gestion locative, travaux d'amélioration.

**Conséquence produit** : la catégorie récupérable/non-récupérable ne devrait pas être une case à cocher libre — elle doit être **dérivée ou fortement suggérée par la nature choisie**, pour éviter qu'un bailleur classe par erreur une dépense non-récupérable comme récupérable (risque juridique direct : sur-facturation illégale au locataire, cf. FEAT-029 déjà noté). Le champ nature devrait donc porter une catégorie par défaut, avec la possibilité de l'ajuster au cas par cas (certaines natures comme « travaux » sont mixtes selon la nature exacte des travaux).

### Rattachement bien / bail / période

- **Bien** : rattachement systématique et obligatoire — une dépense concerne toujours un bien précis (cohérent avec `property.propertyTaxAnnualCents` etc., qui sont déjà au niveau bien).
- **Bail** : rattachement optionnel. Une dépense de copropriété concerne le bien indépendamment du bail en cours (et peut survivre à un changement de locataire) ; en revanche, pour ventiler la régularisation, il faut savoir **quel bail était actif sur la période de rattachement** — voir Décision produit ci-dessous sur ce point précis, car c'est structurant.
- **Période** : nécessaire pour l'agrégation en régularisation (« quelles dépenses récupérables sont tombées sur l'exercice 2025 de ce bail ? »). Peut être dérivée de la date de la dépense par défaut, avec possibilité de correction manuelle (décalage exercice syndic vs année civile, fréquent en copropriété).

## Relations avec l'existant

### FEAT-029 (régularisation de charges)

Aujourd'hui : le bailleur saisit manuellement le total des dépenses réelles dans un dialogue, non persisté. **Avec FEAT-041** : le total des dépenses réelles de la régularisation devient la **somme des Dépenses récupérables** enregistrées sur le bien, dont la période de rattachement chevauche la période de régularisation et (si le rattachement bail est retenu — cf. Décision) qui sont liées au bail concerné. Le bailleur n'a plus à ressaisir ce total ; il vérifie et valide un montant déjà calculé, avec le détail (liste des dépenses + justificatifs) consultable en un clic. Le calcul des provisions encaissées (`payments.chargesAmountCents`) ne change pas.

### FEAT-033 (archivage de la régularisation) — absorption

FEAT-033 visait à créer un objet persistant et immuable pour chaque régularisation validée (pattern `receipts`), afin de retrouver l'historique en cas de litige. **Avec FEAT-041, cet objectif est atteint différemment** : les Dépenses elles-mêmes sont persistées, catégorisées, justifiées et datées dès leur saisie — l'historique existe donc en amont de toute régularisation, dépense par dépense, pas seulement au moment où une régularisation est validée. Il reste toutefois un besoin propre à FEAT-033 que FEAT-041 seul ne couvre pas : **figer un instantané** de la régularisation calculée (le solde, le PDF envoyé, la date de validation) — car les Dépenses en amont pourraient théoriquement être modifiées après coup (correction d'une saisie), alors qu'un avis de régularisation déjà envoyé au locataire doit rester une preuve figée. **Recommandation** : FEAT-041 V1 couvre l'historique des dépenses (justificatif + traçabilité), et un besoin résiduel d'« instantané figé de la régularisation validée » reste à trancher (V1 ou V1.1 — cf. Décisions).

### FEAT-017 (rentabilité) / FEAT-018 (simulateur)

FEAT-017 calcule un rendement net et un cash-flow à partir de trois champs statiques du bien (`propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`), saisis une fois et jamais confrontés au réel. **Avec FEAT-041**, la somme des Dépenses non-récupérables (+ récupérables non refacturées, le cas échéant) d'un bien sur une période peut se substituer à ces estimations, ou les compléter. **Question ouverte, à trancher, pas ici** : remplacer entièrement les 3 champs statiques par le calcul sur dépenses réelles, ou les faire coexister (estimation utilisée tant qu'il n'y a pas assez de dépenses réelles enregistrées, ex. bien récemment acquis) ? Le simulateur (FEAT-018), lui, raisonne sur des scénarios hypothétiques *avant achat* — il n'a par construction aucune dépense réelle à consommer, et devrait continuer à fonctionner sur des estimations saisies manuellement, indépendamment de FEAT-041.

### FEAT-036 (charges récupérables/non-récupérables du bail)

FEAT-036 porte sur la **provision** votée avec le loyer (`lease.chargesAmountCents` scindé récupérable/non-récupérable) — c'est de l'argent **encaissé** par avance. FEAT-041 porte sur l'argent **dépensé** réellement par le bailleur. Les deux sont complémentaires et se rencontrent au moment de la régularisation : provisions encaissées (FEAT-036) vs dépenses réelles récupérables (FEAT-041) = solde. FEAT-041 ne modifie pas le modèle de FEAT-036, il le consomme.

### Système de documents/justificatifs existant (FEAT-009)

Le justificatif d'une Dépense devrait réutiliser la collection `documents` déjà existante (upload, `legalHold`, catégorisation), plutôt que créer un système de pièce-jointe dédié — cohérent avec la façon dont FEAT-029 V1 envisageait déjà de réutiliser `documents` pour l'avis de régularisation. Une nouvelle valeur de catégorie de document (ex. `expense_receipt` ou équivalent) serait probablement nécessaire — détail technique laissé à l'architecte.

### Devenir des 3 champs statiques du bien (`property.propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`)

**Question posée, pas tranchée ici** (cf. Décisions) : ces champs doivent-ils être migrés vers des Dépenses (une dépense annuelle récurrente par champ, à la mise en route de FEAT-041), coexister comme fallback tant qu'aucune dépense réelle n'existe sur le bien, ou rester en l'état pour l'usage "simulateur avant achat" uniquement pendant que FEAT-041 devient la seule source pour les biens déjà en portefeuille ? Les trois options ont un impact différent sur FEAT-017 et méritent une décision produit explicite avant chiffrage technique.

## Périmètre V1 vs hors-V1

### V1 — CRUD Dépense + catégorisation + justificatif + alimentation régularisation

1. **Créer/consulter/modifier/supprimer une Dépense** : date, montant, bien (obligatoire), bail (optionnel), nature (liste fermée), catégorie récupérable/non-récupérable (dérivée de la nature, ajustable), période de rattachement, justificatif (optionnel à la création, fortement recommandé), notes libres.
2. **Historique des dépenses d'un bien** : liste consultable depuis la fiche bien, filtrable par période et par catégorie/nature, avec accès direct au justificatif.
3. **Alimentation automatique de la régularisation (FEAT-029)** : le total des dépenses réelles d'une régularisation est pré-rempli par la somme des Dépenses récupérables du bien/bail sur la période concernée, avec le détail consultable ; le bailleur peut encore ajuster manuellement si besoin (transition douce, pas de confiance aveugle immédiate dans l'agrégation automatique la première fois).
4. **Traçabilité minimale (absorption partielle de FEAT-033)** : chaque Dépense conserve sa date de création, n'est jamais silencieusement écrasée (modification traçée a minima par un horodatage de mise à jour), et son justificatif suit la même règle de rétention que les autres documents légaux.

### V1.1 (hors V1, mais rapproché — à planifier juste après)

- **Rentabilité sur dépenses réelles (FEAT-017)** : agrégation des Dépenses non-récupérables (et récupérables non refacturées) pour calculer le rendement net/cash-flow, en remplacement ou complément des 3 champs statiques (décision produit requise avant, cf. Décisions).
- **Instantané figé de la régularisation validée** (reliquat FEAT-033) : si jugé nécessaire après usage V1, un objet immuable capturant le solde calculé + la liste des dépenses qui le composent au moment de la validation, pour se prémunir d'une modification a posteriori d'une Dépense déjà utilisée dans une régularisation envoyée au locataire.

### Hors scope (V2+)

- Ventilation ligne à ligne d'un décompte syndic multi-natures en une seule saisie (aujourd'hui : une Dépense = une nature ; un décompte syndic réel mélange souvent plusieurs natures — nécessiterait une saisie "décompte" avec plusieurs lignes de Dépenses liées).
- OCR / import automatique d'une facture ou d'un décompte syndic pour pré-remplir une Dépense.
- Dépenses récurrentes automatiques (ex. générer chaque année une Dépense "taxe foncière" sans ressaisie).
- Rapprochement bancaire automatique entre une Dépense et un virement sortant.
- Répartition d'une même Dépense sur plusieurs biens (ex. facture groupée syndic sur un immeuble avec plusieurs lots détenus par le même bailleur).
- Export comptable dédié aux dépenses (peut rejoindre FEAT-032 Export FEC/CSV plus tard).

## Acceptance criteria (Gherkin) — V1

```gherkin
Fonctionnalité : Enregistrer une dépense

Scénario : bailleur enregistre une dépense récupérable avec justificatif
  Given je suis sur la fiche d'un bien
  When j'ajoute une nouvelle dépense avec nature "Charges de copropriété (syndic)"
  And un montant de 450,00 €, une date de facture du 15/03/2026
  And une période de rattachement "exercice 2025"
  And un justificatif PDF joint (décompte syndic)
  Then la catégorie "récupérable" est présélectionnée automatiquement pour cette nature
  And la dépense apparaît dans l'historique du bien avec son justificatif accessible

Scénario : bailleur enregistre une dépense non-récupérable
  Given je suis sur la fiche d'un bien
  When j'ajoute une nouvelle dépense avec nature "Taxe foncière"
  Then la catégorie "non-récupérable" est présélectionnée automatiquement et non modifiable
    (ou modifiable avec avertissement explicite, selon décision produit)

Fonctionnalité : Historique des dépenses d'un bien

Scénario : bailleur consulte l'historique filtré par période
  Given un bien avec 8 dépenses enregistrées sur 2 exercices différents
  When le bailleur filtre l'historique sur l'exercice 2025
  Then seules les dépenses rattachées à l'exercice 2025 sont affichées
  And le total récupérable et le total non-récupérable de la période sont affichés séparément

Fonctionnalité : Régularisation alimentée par les dépenses enregistrées

Scénario : le total des dépenses réelles est pré-rempli automatiquement
  Given un bail nu avec des dépenses récupérables enregistrées sur la période 01/01/2025-31/12/2025
    totalisant 980,00 €
  When le bailleur ouvre l'action "Régularisation annuelle des charges" pour ce bail
  Then le total des dépenses réelles est pré-rempli à 980,00 € (au lieu d'une saisie manuelle)
  And le détail des dépenses qui composent ce total est consultable (liste + justificatifs)
  And le bailleur peut encore ajuster ce montant manuellement avant validation

Fonctionnalité : Rentabilité (V1.1 — hors V1, acceptance à titre indicatif)

Scénario : le rendement net utilise les dépenses réelles plutôt que l'estimation statique
  Given un bien avec des dépenses non-récupérables réelles enregistrées sur les 12 derniers mois
  When le bailleur consulte la section "Rentabilité" de la fiche bien
  Then le rendement net est calculé à partir de la somme des dépenses réelles de la période
    (et non plus depuis les champs statiques du bien), selon la règle de bascule tranchée en Décision
```

## Legal / compliance notes

- **Décret n°87-713 du 26 août 1987** : liste limitative des charges récupérables auprès du locataire. La catégorisation récupérable/non-récupérable d'une Dépense doit s'appuyer sur cette liste — un mauvais classement expose le bailleur à une contestation locataire fondée (charge indûment répercutée). Le champ "nature" doit rester une liste fermée alignée sur ce décret pour limiter ce risque, pas un texte libre.
- **Valeur probante et rétention des justificatifs** : en cas de litige locatif ou de contrôle fiscal, le justificatif d'une dépense récupérable (facture, décompte syndic) constitue la preuve du bien-fondé de la régularisation transmise au locataire. Conservation alignée sur la règle déjà en vigueur (`docs/LEGAL.md`) : **5 ans minimum** pour les documents à valeur probante locative (même régime que les quittances) ; **10 ans** si le document a par ailleurs une portée comptable (factures de travaux déductibles, par exemple, relèvent du code de commerce). Les justificatifs de Dépense doivent donc porter la même protection `legalHold` que les autres documents légaux du système existant — pas de suppression libre tant que la rétention n'est pas expirée.
- **RGPD** : une Dépense ne porte pas nécessairement de données personnelles du locataire (elle concerne le bien), sauf si le libellé/notes ou le justificatif mentionne le locataire nommément (ex. facture de réparation demandée par le locataire). Pas de traitement spécifique supplémentaire nécessaire au-delà des règles déjà appliquées aux documents (RLS, accès restreint au bailleur propriétaire).
- **Non-mélange récupérable/non-récupérable dans le calcul du solde de régularisation** : reprise explicite de la mise en garde déjà actée dans FEAT-029 — seules les dépenses de catégorie récupérable doivent entrer dans le solde transmis au locataire.

## Dependencies

- **Entités concernées** : nouvelle entité "Dépense" (rattachée à un bien, optionnellement à un bail) ; `documents` existant (justificatif) ; `leases` (lecture pour le rattachement bail et le calcul de régularisation FEAT-029) ; `properties` (rattachement obligatoire, et potentiellement migration/coexistence des 3 champs statiques de coûts annuels).
- **Features bloquantes / à coordonner** :
  - FEAT-029 (régularisation) — déjà livrée V1, à faire évoluer pour consommer les Dépenses au lieu de la saisie manuelle.
  - FEAT-036 (charges récupérables/non-récupérables du bail) — complémentaire, pas bloquante, mais la cohérence terminologique (même notion de "récupérable") doit être gardée entre les deux features.
  - FEAT-033 (archivage régularisation) — largement absorbée par FEAT-041 V1 (cf. section dédiée) ; le reliquat "instantané figé" reste à statuer en V1.1.
  - FEAT-017 / FEAT-018 (rentabilité/simulateur) — FEAT-017 concerné par le passage aux dépenses réelles (V1.1) ; FEAT-018 hors sujet (raisonne sur des scénarios avant achat, pas de dépenses réelles).
  - FEAT-009 (documents) — réutilisé tel quel pour le justificatif.

## Décisions produit à trancher par l'utilisateur

1. **Rattachement bail précis ou seulement bien ?** Une Dépense doit-elle obligatoirement pouvoir être liée à un bail (pour ventiler la régularisation quand plusieurs baux se sont succédé sur la période), ou le rattachement au bien seul suffit-il, avec la ventilation par bail déduite implicitement de la période de rattachement + des dates du bail ? **Recommandation** : rattachement bail **optionnel** mais fortement suggéré au moment de la saisie si un bail est actif sur la période choisie — évite d'imposer une saisie que le bailleur ne sait pas toujours renseigner sur le moment (le décompte syndic arrive souvent après un changement de locataire), tout en gardant la précision nécessaire quand elle est disponible.

2. **Catégorie récupérable/non-récupérable : dérivée strictement de la nature, ou ajustable au cas par cas ?** Certaines natures (ex. "travaux") sont mixtes selon le détail réel des travaux. **Recommandation** : présélection automatique par nature + possibilité d'ajuster manuellement, avec un avertissement explicite si le bailleur bascule une nature normalement non-récupérable vers récupérable (pas de blocage dur, mais pas de silence non plus — risque juridique direct sinon).

3. **Liste des natures : fermée et imposée, ou extensible par l'utilisateur ?** Une liste fermée aligée sur le décret n°87-713 sécurise juridiquement mais peut frustrer un cas réel non prévu. **Recommandation** : liste fermée en V1 (couvre l'essentiel : syndic/charges copro, taxe foncière, assurance PNO, travaux, réparation/entretien, gestion locative, autre) avec une valeur "autre" en secours plutôt qu'une liste libre — réduit le risque de mauvaise catégorisation.

4. **Devenir des 3 champs statiques du bien (`propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`)** : migration en Dépenses initiales, coexistence en fallback (utilisés tant qu'aucune dépense réelle n'existe sur le bien/l'année), ou conservation en l'état pour un usage distinct (estimation prévisionnelle vs FEAT-041 = réel constaté) ? **Recommandation** : coexistence en fallback pour V1.1 — évite une migration de données risquée et un rendement net qui tomberait brutalement à zéro pour un bien fraîchement ajouté sans historique de dépenses réelles ; bascule complète vers le réel envisageable plus tard une fois l'usage confirmé.

5. **Rentabilité sur réel — inclus dès V1, ou V1.1 séparée ?** Le brief l'évoque comme "peut-être V1.1". **Recommandation** : V1.1, séparée du CRUD Dépense — la valeur du CRUD + alimentation régularisation (V1) est déjà livrable et testable seule ; coupler la bascule de FEAT-017 dans le même chantier augmente le risque de dépasser 3 jours par story et mélange deux décisions produit indépendantes (cf. décision 4).

6. **Reliquat FEAT-033 (instantané figé de la régularisation validée)** : nécessaire dès V1, ou acceptable de différer tant que les Dépenses sources restent consultables et que leur modification est tracée (horodatage) ? **Recommandation** : différer en V1.1 — le risque (une Dépense modifiée après l'envoi d'une régularisation au locataire) est réel mais rare, et le tracé par horodatage de mise à jour en V1 donne déjà une traçabilité minimale suffisante pour démarrer.

7. **Saisie manuelle vs futur OCR du décompte syndic** : le brief mentionne l'OCR comme perspective. **Recommandation** : saisie manuelle stricte en V1 (déjà cohérent avec le hors-scope de FEAT-029 qui reportait l'OCR à P2) — l'OCR de décompte syndic est un chantier lourd et distinct (extraction multi-lignes, multi-natures) à cadrer séparément le moment venu, pas un prérequis à la valeur de FEAT-041 V1.

## Priority

P1 (post-MVP) — absorbe et remplace le périmètre restant de FEAT-033 dans le classement RICE existant (`docs/BACKLOG.md`), synergise directement avec FEAT-029 (déjà livrée) et FEAT-036 (en cours de cadrage/priorisation).

## Estimated effort

**Cadrage uniquement livré ici.** Pour le V1 tel que scopé ci-dessus, une fois les décisions ci-dessus tranchées :

- CRUD Dépense (formulaire + liste + historique filtrable, sans justificatif) : **M** (1-3 jours).
- Intégration justificatif (réutilisation `documents`) : **S** à **M** selon la décision technique de l'architecte sur l'extension de `documents.category`.
- Alimentation automatique de la régularisation (FEAT-029) : **M** — modifie le calcul existant côté `charge_regularization/**`, doit rester non-bloquant (ajustement manuel possible).
- Total V1 : **L** (> 3 jours cumulés) — à re-découper par l'architecte en sous-tickets (CRUD isolé / justificatif / intégration régularisation) pour rester sous la règle "story < 3 jours" par sous-ticket.
- V1.1 (rentabilité sur réel + reliquat FEAT-033) : non chiffré ici, dépend des décisions 4/5/6 ci-dessus.

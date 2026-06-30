# [FEAT-017] Rentabilité du portfolio — rendement brut, net et cash-flow

## User story
En tant que **bailleur français possédant 1 à 10 biens**, je veux **saisir les données financières d'acquisition et de charges de mes biens et voir automatiquement le rendement brut, le rendement net et le cash-flow mensuel** afin de **savoir concrètement combien je gagne par rapport à ce que j'ai investi, et comparer ma performance au marché français**.

## Context & motivation
Aujourd'hui EasyRent permet d'enregistrer les paiements et de générer des quittances, mais n'a aucune vue rentabilité. Un bailleur qui veut savoir s'il gagne de l'argent doit sortir une calculette. La douleur : impossibilité de piloter son portfolio depuis l'outil, perte de confiance dans le produit pour les utilisateurs qui ont plusieurs biens. La donnée brute existe déjà (loyers dans `payments`, baux dans `leases`) mais le dénominateur (prix d'achat, charges fixes) est absent du schéma.

Hypothèses posées :
- Benchmarks FR retenus : rendement brut médian 5–7 % (source : FNAIM 2024), seuil "correct" fixé à 5 % brut, seuil "bon" à 7 %.
- Régime fiscal hors scope v1 (le type bail `lease_type` permet d'inférer micro-foncier vs micro-BIC mais le choix réel/micro n'est pas stocké ni calculé ici).
- Un seul scénario prêt actif par bien (table `loan_scenarios`).
- Montants en `bigint cents`, taux en `bps` (1 bps = 0,01 %), dates en `date` — convention EasyRent FEAT-014.

---

## Acceptance criteria (Gherkin)

### Story 1 — Saisie des données financières d'acquisition (Phase 1 : colonnes `properties`)

**Given** un bailleur connecté sur la page d'édition d'un bien (PropertyFormPage)
**When** il ouvre la section "Finances & acquisition"
**Then** il voit les champs : prix d'achat (€), date d'achat, frais de notaire (€), taxe foncière annuelle (€), assurance PNO annuelle (€), charges copropriété annuelles (€)

**Given** le bailleur saisit un prix d'achat de 150 000 €
**When** il sauvegarde
**Then** `properties.purchase_price_cents = 15000000` est persisté en base

**Given** le bailleur laisse le prix d'achat vide
**When** il sauvegarde
**Then** la sauvegarde passe sans erreur (champs optionnels), les KPIs rentabilité affichent "Données manquantes" sur la page détail

**Given** le bailleur saisit une taxe foncière de 1 200 €/an
**When** il sauvegarde
**Then** `properties.property_tax_annual_cents = 120000`

### Story 2 — Saisie du scénario de prêt (Phase 2 : table `loan_scenarios`)

**Given** un bailleur sur la page détail d'un bien
**When** il clique "Ajouter un prêt immobilier"
**Then** un formulaire s'ouvre avec : capital emprunté (€), apport personnel (€), taux d'intérêt (% sur 2 décimales), taux assurance (% sur 2 décimales), durée (mois), date de début

**Given** le bailleur saisit capital=120 000 €, apport=30 000 €, taux=3,25 %, assurance=0,10 %, durée=240 mois
**When** il sauvegarde
**Then** un enregistrement `loan_scenarios` est créé avec `is_active=true`, `interest_rate_bps=325`, `insurance_rate_bps=10`

**Given** le bailleur tente d'ajouter un second prêt actif sur le même bien
**When** il sauvegarde
**Then** le système désactive automatiquement l'ancien (`is_active=false`) et active le nouveau (contrainte "1 actif par bien")

**Given** aucun scénario prêt n'est renseigné
**When** le bailleur consulte les KPIs du bien
**Then** le cash-flow affiche "Non calculé (prêt manquant)" et les autres KPIs restent visibles si le prix d'achat est présent

### Story 3 — KPIs rentabilité sur la page détail d'un bien

**Given** un bien avec `purchase_price_cents` renseigné et un bail actif
**When** le bailleur consulte PropertyDetailPage
**Then** il voit la section "Rentabilité" affichant :
  - Rendement brut = (loyer annuel HC × 12) / prix total acquisition × 100 %
    - prix total acquisition = purchase_price_cents + notary_fees_cents (si renseigné)
  - Code couleur : rouge < 5 %, orange 5–7 %, vert > 7 %

**Given** le bien a `property_tax_annual_cents`, `insurance_pno_annual_cents`, `condo_fees_annual_cents` renseignés
**When** le bailleur consulte la section "Rentabilité"
**Then** il voit :
  - Rendement net = (loyer annuel HC − charges annuelles nettes) / prix total acquisition × 100 %
    - charges annuelles nettes = taxe foncière + assurance PNO + charges copro non récupérables
  - Affichage détail des charges déduites (tooltip ou expand)

**Given** un scénario prêt actif avec mensualité calculée
**When** le bailleur consulte la section "Rentabilité"
**Then** il voit :
  - Cash-flow mensuel = loyer HC encaissé (mois courant ou moyen 12 mois) − mensualité prêt − (charges annuelles nettes / 12)
  - Positif affiché en vert, négatif en rouge

**Given** le bailleur survole ou tape le rendement brut
**Then** une info-bulle explique la formule : "Loyer annuel HC (X €) / Prix d'acquisition (Y €)"

**Given** la mensualité n'est pas saisie manuellement
**When** le prêt a capital, taux, assurance et durée renseignés
**Then** la mensualité est calculée automatiquement côté client via la formule d'amortissement à taux fixe (M = C × (t/12) / (1 − (1+t/12)^−n) + assurance)

### Story 4 — Vue portfolio (Dashboard)

**Given** un bailleur avec au moins un bien ayant un prix d'achat renseigné
**When** il consulte le Dashboard
**Then** il voit trois nouveaux KPI cards dans la section "Rentabilité portfolio" :
  - Rendement brut moyen du portfolio (moyenne pondérée par prix d'acquisition)
  - Rendement net moyen du portfolio
  - Cash-flow mensuel total (somme des cash-flows des biens avec prêt)

**Given** un bailleur avec 3 biens dont 1 sans prix d'achat
**When** il consulte le Dashboard
**Then** les KPIs sont calculés sur les 2 biens avec données complètes, et une mention "1 bien sans données" est affichée

**Given** le rendement brut moyen du portfolio est de 6,2 %
**When** le bailleur consulte la card "Rendement brut moyen"
**Then** il voit le badge "Dans la norme FR (5–7 %)" en orange-amber

**Given** le rendement brut moyen est > 7 %
**Then** le badge affiche "Au-dessus de la médiane FR" en vert

**Given** le rendement brut moyen est < 5 %
**Then** le badge affiche "En dessous de la médiane FR" en rouge

### Story 5 — Fiabilité et règles métier des calculs

**Given** un bail `status = 'inactive'` ou `deleted_at IS NOT NULL`
**When** les KPIs sont calculés
**Then** le loyer de ce bail n'est PAS inclus dans le loyer annuel théorique

**Given** le loyer annuel encaissé est calculé
**When** le calcul est effectué
**Then** il utilise la somme `payments.rent_amount_cents` sur les 12 derniers mois glissants (non les charges récupérables)

**Given** aucun paiement sur les 12 derniers mois (bail récent < 12 mois)
**When** les KPIs de rendement sont calculés
**Then** le loyer annualisé = `lease.rent_amount_cents × 12` (loyer contractuel, pas encaissé) avec mention "Loyer contractuel annualisé"

---

## Out of scope

- TRI (Taux de Rendement Interne) multi-périodes
- Comparaison entre régimes fiscaux (micro-foncier vs réel vs micro-BIC vs LMNP) — P2
- Suivi historique de l'évolution du rendement (graphe temporel) — P2
- Export PDF rapport de rentabilité
- Table `property_expenses` pour charges ponctuelles datées (travaux déductibles) — post-v1
- Table `rent_revisions` pour historique IRL complet
- Revalorisation automatique du loyer via IRL
- Valorisation de marché automatique (API prix immobilier)
- Cash-flow après impôt (nécessite régime fiscal confirmé)

---

## Dependencies

### Tables Supabase

**Migration Phase 1 — colonnes ajoutées à `properties`** :
- `purchase_price_cents` bigint NULL
- `purchase_date` date NULL
- `notary_fees_cents` bigint NULL
- `property_tax_annual_cents` bigint NULL
- `insurance_pno_annual_cents` bigint NULL
- `condo_fees_annual_cents` bigint NULL

**Migration Phase 2 — nouvelle table `loan_scenarios`** :
```
loan_scenarios (
  id uuid PK DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES properties(id) ON DELETE RESTRICT,
  landlord_id uuid NOT NULL REFERENCES landlords(id),
  principal_cents bigint NOT NULL CHECK (principal_cents > 0),
  down_payment_cents bigint NOT NULL DEFAULT 0,
  interest_rate_bps int NOT NULL CHECK (interest_rate_bps >= 0),
  insurance_rate_bps int NOT NULL DEFAULT 0,
  duration_months smallint NOT NULL CHECK (duration_months > 0),
  start_date date NOT NULL,
  monthly_payment_cents bigint NULL,  -- cache calculé, nullable
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz NULL
)
```
- RLS : SELECT/INSERT/UPDATE filtrés sur `landlord_id = auth.uid()`
- Trigger tr_00 (ownership), tr_01 (protect deleted_at), tr_02 (updated_at) — pattern standard EasyRent
- Contrainte unicité logique : 1 seul `is_active=true` par `property_id` (enforcer via trigger ou partial unique index)

### Features bloquantes
- FEAT-003 (CRUD propriétés) — page détail + formulaire à étendre ✅
- FEAT-005 (CRUD baux) — loyer contractuel ✅
- FEAT-006 (paiements) — loyer encaissé ✅
- FEAT-010 (dashboard KPI cards + KpiGrid) — réutilisation widgets ✅
- FEAT-014 (colonnes financières enrichies) — cohérence convention cents ✅

---

## Legal / compliance notes

- Données financières personnelles (prix d'achat, revenus locatifs) : soumises au RGPD. RLS obligatoire — seul le propriétaire du bien y accède.
- Conservation : alignée sur les autres données (5 ans minimum — loi 89-462 pour les baux, prescription fiscale 3 ans + délai prudentiel).
- Les benchmarks affichés (médiane FR 5–7 %) sont des indicateurs informatifs. Aucun conseil fiscal ou financier ne doit être inféré de l'affichage. Ajouter une mention de bas de page : *"Les rendements affichés sont des indicateurs informatifs calculés sur la base des données saisies. Ils ne constituent pas un conseil en investissement."*
- Pas de transmission des données financières à des tiers sans consentement explicite (RGPD art. 6).

---

## Priority
P1 (post-MVP immédiat — première extension significative après le MVP)

## Estimated effort
L (> 3 jours) — décomposé en 3 phases :
- Phase 1 (migration + formulaire propriété) : M (1–2 jours)
- Phase 2 (table loan_scenarios + formulaire) : M (1–2 jours)
- Phase 3 (calculs + affichage KPIs détail + dashboard) : M (2–3 jours)

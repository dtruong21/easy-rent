# [FEAT-018] Simulateur d'investissement locatif

## User story
En tant que **bailleur potentiel**, je veux **simuler la rentabilité d'un bien avant de l'acheter** afin de **comparer des scénarios d'acquisition et décider en connaissance de cause**.

## Context & motivation

Le dashboard actuel est 100% opérationnel (paiements, retards, documents). Il n'existe aucun outil de projection financière dans EasyRent. Un bailleur qui envisage un achat doit aujourd'hui utiliser une feuille de calcul externe.

Le simulateur est **entièrement découplé des biens existants** : il s'agit d'un espace « bac à sable » où l'utilisateur saisit les paramètres d'un projet et lit les indicateurs calculés en temps réel, sans jamais impacter les données locatives réelles.

Hypothèses retenues (assumptions PO) :
- Les scénarios sauvegardés sont liés au compte `landlord_id` (RLS standard).
- Un scénario = un bien hypothétique + un financement + des paramètres d'exploitation.
- La fiscalité détaillée (abattement micro vs régime réel) est **hors scope v1** : on affiche uniquement les indicateurs bruts/nets avant impôt.
- La valeur future du bien est un calcul de revalorisation annuelle paramétrable (%, non une API externe).
- La comparaison de scénarios est limitée à **3 scénarios** affichés côte à côte (table ou colonnes).

## Acceptance criteria (Gherkin)

### US-018-1 — Accès à la page simulateur

- **Given** un utilisateur authentifié
  **When** il navigue vers `/simulator`
  **Then** la page s'affiche avec un formulaire vierge par défaut et un bouton « Nouveau scénario ».

- **Given** un utilisateur non authentifié
  **When** il accède à `/simulator`
  **Then** il est redirigé vers `/login` (comportement GoRouter garde déjà en place).

### US-018-2 — Saisie du formulaire de scénario

- **Given** l'utilisateur est sur `/simulator`
  **When** il remplit les champs du formulaire :
  - Nom du scénario (texte libre, max 80 car.)
  - Prix d'achat (€, entier positif, obligatoire)
  - Frais de notaire (€ ou %, défaut calculé à 7,5 % du prix ancien)
  - Apport personnel (€, >= 0, obligatoire)
  - Taux d'intérêt annuel (%, 2 décimales, obligatoire)
  - Durée du prêt (mois, entre 12 et 360, obligatoire)
  - Assurance emprunteur (% annuel sur capital initial, défaut 0,30 %)
  - Loyer mensuel attendu HC (€, entier positif, obligatoire)
  - Charges récupérables mensuelles (€, >= 0)
  - Taxe foncière annuelle (€, >= 0)
  - Assurance PNO annuelle (€, >= 0)
  - Charges copropriété annuelles (€, >= 0)
  - Frais de gestion (% du loyer HC, >= 0, défaut 0)
  - Taux de vacance locative estimé (%, 0-100, défaut 5)
  - Travaux initiaux (€, >= 0, défaut 0)
  - Taux de revalorisation annuelle du bien (%, défaut 1,5)
  - Horizon de projection (années, entre 1 et 30, défaut 20)
  **Then** les résultats se mettent à jour en temps réel (ou à la soumission, sans rechargement de page).

- **Given** un champ obligatoire est vide ou invalide
  **When** l'utilisateur tente de calculer ou sauvegarder
  **Then** un message d'erreur inline s'affiche sous le champ concerné et les résultats ne s'affichent pas.

- **Given** l'apport est supérieur au prix d'achat + frais de notaire
  **When** le formulaire est soumis
  **Then** une erreur « L'apport ne peut pas dépasser le coût total d'acquisition » s'affiche.

### US-018-3 — Affichage des résultats calculés

- **Given** le formulaire est valide
  **When** les résultats sont affichés
  **Then** les indicateurs suivants sont visibles, chacun avec libellé et valeur formatée :

  | Indicateur | Formule attendue |
  |---|---|
  | Mensualité prêt (PI) | Formule annuité constante sur capital emprunté |
  | Mensualité assurance emprunteur | (capital × taux_assurance) / 12 |
  | Mensualité totale emprunt | PI + assurance |
  | Loyer net annuel (vacance déduite) | loyer_hc × 12 × (1 - vacance%) |
  | Charges non récupérables annuelles | taxe_foncière + PNO + charges_copro_non_récup + frais_gestion |
  | Revenu net avant impôt annuel | loyer_net_annuel - charges_non_récup |
  | Cash-flow mensuel | (revenu_net_annuel / 12) - mensualité_totale |
  | Rendement brut | (loyer_hc × 12) / coût_acquisition_total × 100 |
  | Rendement net (avant impôt) | revenu_net_annuel / coût_acquisition_total × 100 |
  | Total intérêts versés | somme des intérêts sur durée du prêt |
  | Coût total du crédit | total_intérêts + total_assurance_emprunteur |
  | Valeur estimée à terme (horizon) | prix_achat × (1 + taux_revalorisation%)^horizon |
  | Plus-value brute estimée | valeur_terme - coût_acquisition_total |

- **Given** le cash-flow mensuel est négatif
  **When** les résultats sont affichés
  **Then** la valeur est affichée en rouge avec le signe « - ».

- **Given** le cash-flow mensuel est positif ou nul
  **When** les résultats sont affichés
  **Then** la valeur est affichée en vert.

- **Given** le rendement brut est calculé
  **When** les résultats sont affichés
  **Then** un indicateur visuel (couleur ou icône) signale si le rendement est < 3 % (faible), 3-6 % (correct), > 6 % (élevé) — selon les seuils usuels du marché français.

### US-018-4 — Sauvegarde d'un scénario

- **Given** le formulaire est valide et l'utilisateur clique sur « Sauvegarder »
  **When** la sauvegarde réussit
  **Then** le scénario apparaît dans la liste des scénarios sauvegardés sur la même page (ou section dédiée) avec son nom et la date de création.

- **Given** un scénario est sauvegardé
  **When** l'utilisateur le sélectionne dans la liste
  **Then** le formulaire se remplit avec les valeurs du scénario et les résultats se recalculent.

- **Given** un utilisateur possède un scénario
  **When** un autre utilisateur (autre `landlord_id`) tente d'y accéder via son `id`
  **Then** Supabase retourne 0 résultat (RLS appliquée).

- **Given** l'utilisateur clique sur « Supprimer » sur un scénario sauvegardé
  **When** il confirme la suppression
  **Then** le scénario est supprimé (hard delete acceptable — pas de valeur légale, pas de rétention obligatoire).

### US-018-5 — Comparaison de scénarios

- **Given** l'utilisateur a au moins 2 scénarios sauvegardés
  **When** il sélectionne 2 ou 3 scénarios via des cases à cocher et clique sur « Comparer »
  **Then** une vue comparative s'affiche avec les indicateurs-clés côte à côte (mensualité, cash-flow, rendement brut, rendement net, valeur à terme).

- **Given** l'utilisateur sélectionne plus de 3 scénarios
  **When** il tente d'activer la comparaison
  **Then** un message « La comparaison est limitée à 3 scénarios simultanément » s'affiche.

### US-018-6 — Navigation et persistance de session

- **Given** l'utilisateur est en train de saisir un formulaire non sauvegardé
  **When** il navigue vers une autre page puis revient sur `/simulator`
  **Then** le formulaire est réinitialisé (pas de sauvegarde automatique brouillon en v1 — assumption documentée).

## Data model

### Nouvelle table `investment_scenarios`

```sql
CREATE TABLE investment_scenarios (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id                 uuid NOT NULL REFERENCES landlords(id) ON DELETE RESTRICT,
  name                        text NOT NULL CHECK (char_length(name) <= 80),

  -- Acquisition
  purchase_price_cents        bigint NOT NULL CHECK (purchase_price_cents > 0),
  notary_fees_cents           bigint NOT NULL DEFAULT 0 CHECK (notary_fees_cents >= 0),
  works_initial_cents         bigint NOT NULL DEFAULT 0 CHECK (works_initial_cents >= 0),
  down_payment_cents          bigint NOT NULL CHECK (down_payment_cents >= 0),

  -- Prêt
  loan_principal_cents        bigint NOT NULL CHECK (loan_principal_cents >= 0),
  interest_rate_bps           int NOT NULL CHECK (interest_rate_bps >= 0),
  loan_duration_months        smallint NOT NULL CHECK (loan_duration_months BETWEEN 12 AND 360),
  insurance_rate_bps          int NOT NULL DEFAULT 30 CHECK (insurance_rate_bps >= 0),

  -- Exploitation
  monthly_rent_hc_cents       bigint NOT NULL CHECK (monthly_rent_hc_cents > 0),
  monthly_charges_cents       bigint NOT NULL DEFAULT 0 CHECK (monthly_charges_cents >= 0),
  property_tax_annual_cents   bigint NOT NULL DEFAULT 0 CHECK (property_tax_annual_cents >= 0),
  insurance_pno_annual_cents  bigint NOT NULL DEFAULT 0 CHECK (insurance_pno_annual_cents >= 0),
  condo_fees_annual_cents     bigint NOT NULL DEFAULT 0 CHECK (condo_fees_annual_cents >= 0),
  management_fees_pct         numeric(5,2) NOT NULL DEFAULT 0 CHECK (management_fees_pct BETWEEN 0 AND 50),
  vacancy_rate_pct            numeric(5,2) NOT NULL DEFAULT 5 CHECK (vacancy_rate_pct BETWEEN 0 AND 100),

  -- Projection
  appreciation_rate_pct       numeric(5,2) NOT NULL DEFAULT 1.5,
  projection_years            smallint NOT NULL DEFAULT 20 CHECK (projection_years BETWEEN 1 AND 30),

  -- Metadata
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now()
);
```

RLS : `landlord_id = auth.uid()` sur SELECT / INSERT / UPDATE / DELETE.
Triggers standard : `tr_01` (protect landlord_id), `tr_02` (updated_at).

Pas de soft-delete : pas de valeur légale, suppression physique acceptable.

Calculs **100% côté client Flutter** (aucune Edge Function nécessaire) — formules mathématiques pures.

## Formules de référence (pour implémentation)

```
capital_emprunté = purchase_price + notary_fees + works_initial - down_payment

# Mensualité PI (annuité constante)
taux_mensuel = interest_rate_bps / 100 / 100 / 12
mensualité_PI = capital × taux_mensuel / (1 - (1 + taux_mensuel)^(-durée_mois))
# Cas taux = 0 : mensualité_PI = capital / durée_mois

mensualité_assurance = capital_emprunté × (insurance_rate_bps / 100 / 100) / 12
mensualité_totale = mensualité_PI + mensualité_assurance

total_intérêts = (mensualité_PI × durée_mois) - capital_emprunté
total_assurance = mensualité_assurance × durée_mois
coût_total_crédit = total_intérêts + total_assurance

loyer_net_annuel = monthly_rent_hc × 12 × (1 - vacancy_rate_pct / 100)
frais_gestion_annuels = monthly_rent_hc × 12 × (management_fees_pct / 100)
charges_non_récup = property_tax + insurance_pno + condo_fees + frais_gestion
revenu_net_annuel = loyer_net_annuel - charges_non_récup

cash_flow_mensuel = (revenu_net_annuel / 12) - mensualité_totale

coût_acquisition_total = purchase_price + notary_fees + works_initial
rendement_brut = (monthly_rent_hc × 12) / coût_acquisition_total × 100
rendement_net = revenu_net_annuel / coût_acquisition_total × 100

valeur_terme = purchase_price × (1 + appreciation_rate_pct / 100)^projection_years
plus_value_brute = valeur_terme - coût_acquisition_total
```

## Out of scope

- Simulation fiscalité détaillée (micro-foncier 30 %, micro-BIC 50 %, régime réel) — P2
- Intégration API prix marché m² par ville (DVF, SeLoger) — P2
- Stress test automatique (hausse de taux, vacance prolongée) — P2
- Export PDF de la projection — P2
- Tableau d'amortissement détaillé (mois par mois) — P2
- Lien vers un bien existant (`properties`) — P1
- Sauvegarde brouillon automatique (session non sauvegardée) — P1
- Partage de scénario entre utilisateurs — P2
- Notifications / alertes sur les scénarios — P2

## Dependencies

- Tables Supabase : nouvelle table `investment_scenarios`
- Features bloquantes : FEAT-002 (landlords + RLS pattern), FEAT-011 (auth)
- Features influencées : FEAT-017 (portfolio rentabilité) peut réutiliser les mêmes formules de calcul — coordination recommandée pour partager un `RentalCalculator` Dart pur.

## Legal / compliance notes

- Les scénarios de simulation ne constituent pas un conseil financier. Une mention disclaimer doit apparaître sur la page : *« Les résultats sont fournis à titre indicatif et ne constituent pas un conseil financier ou fiscal. »*
- Aucune donnée personnelle de tiers (locataire) n'est collectée sur cette page.
- Données du simulateur : appartiennent au bailleur, pas de rétention légale obligatoire — suppression physique acceptable.
- RGPD : les données sont rattachées à `landlord_id`, couvertes par les droits export/effacement du compte propriétaire (à inclure dans la future Edge Function RGPD, P1).

## Priority
P1 (post-MVP) — Le MVP core (FEAT-001–016) est complet. Ce module est la prochaine priorité fonctionnelle après FEAT-017.

## Estimated effort
L (> 3 jours) — Décomposition recommandée :
- **Sprint A** (M) : Migration SQL `investment_scenarios` + RLS + modèle Dart + repository Supabase
- **Sprint B** (M) : Formulaire `/simulator` + calculs temps réel + affichage résultats
- **Sprint C** (S) : Sauvegarde / chargement scénarios + suppression
- **Sprint D** (S) : Vue comparaison 2-3 scénarios

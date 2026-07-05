# FEAT-036 — Charges récupérables / non-récupérables

> **Statut** : 📋 Spec'd (2026-07-05) — priorisé #2 RICE (score 30), TOP 3 validé utilisateur, lancé en 1er (FEAT-031 en pause infra email).
> **Effort estimé** : S (~2j). **Dépend de** : FEAT-005 (baux), FEAT-029 (régularisation) ✅.
> **Priorisation parente** : voir [`../BACKLOG.md`](../BACKLOG.md) (section « Priorisation Post-MVP P1 »).

## Contexte

Aujourd'hui un bail porte un **montant de charges unique** (`chargesAmountCents`, provisions mensuelles). Or la loi distingue les **charges récupérables** (répercutables sur le locataire — liste limitative du **décret n°87-713 du 26 août 1987** : entretien parties communes, taxe d'enlèvement des ordures ménagères, etc.) des **charges non-récupérables** (à la charge du bailleur). Sans cette distinction, la régularisation annuelle livrée en FEAT-029 est juridiquement approximative : elle ne peut pas garantir que seul le récupérable est régularisé auprès du locataire.

FEAT-036 introduit la distinction récupérable / non-récupérable sur le bail et la propage à la régularisation (FEAT-029).

## User story

**En tant que** bailleur,
**je veux** distinguer les charges récupérables des charges non-récupérables sur mon bail,
**afin que** ma régularisation annuelle et mes documents reflètent la répartition légale réelle (décret n°87-713) et soient incontestables par le locataire.

## Périmètre

### Inclus (V1)
- Saisie séparée **récupérable / non-récupérable** dans le formulaire de bail (création + édition).
- Affichage de la ventilation sur la fiche bail.
- Prise en compte par le **calcul de régularisation** (FEAT-029) : seul le récupérable entre dans le solde régularisable.
- **Migration** des baux existants sans perte de données.

### Exclus (hors V1)
- Catégorisation fine poste par poste (eau, chauffage, TEOM…) — V2 éventuelle.
- Modification de la logique de quittance mensuelle au-delà de l'affichage (le loyer + provisions restent inchangés).

## Acceptance criteria

1. **Given** la création ou l'édition d'un bail **When** le bailleur saisit les charges **Then** il renseigne séparément le montant **récupérable** et le montant **non-récupérable** (provisions mensuelles).
2. **Given** une régularisation annuelle (FEAT-029) **When** le calcul du solde s'exécute **Then** seules les charges **récupérables** entrent dans le solde régularisable auprès du locataire.
3. **Given** un bail existant créé avant FEAT-036 (`chargesAmountCents` unique) **When** la migration s'applique **Then** le montant existant est conservé et interprété par défaut comme **récupérable** (non-récupérable = 0), sans perte ni régression.
4. **Given** la fiche d'un bail **When** le bailleur la consulte **Then** il voit la ventilation récupérable / non-récupérable (et le total).
5. **Given** les fonctionnalités existantes (quittance PDF, KPI dashboard, détection retards) **When** FEAT-036 est déployée **Then** aucune régression : le montant total des charges reste cohérent partout où il était utilisé.

## Contraintes légales / conformité

- **Décret n°87-713 du 26 août 1987** : liste limitative des charges récupérables. Une régularisation qui ne distingue pas récupérable / non-récupérable est contestable par le locataire.
- Impact direct sur la conformité de **FEAT-029** (régularisation annuelle) déjà livrée en V1.
- Voir [`../LEGAL.md`](../LEGAL.md).

## Pistes techniques (à valider / affiner par l'architecte)

- **Modèle de données** : le bail porte aujourd'hui `chargesAmountCents` (montant unique, camelCase Firestore — cf. dette `SCHEMA.md` corrigée par l'architecte FEAT-031). Options : (a) ajouter `recoverableChargesCents` + `nonRecoverableChargesCents` et déprécier/dériver `chargesAmountCents` (= somme), ou (b) sous-map `charges: { recoverable, nonRecoverable }`. **Point de décision architecte** — préserver la rétrocompat du total.
- **`leases` est CF-exclusive** → écriture via callables `createLease` / `updateLease` (validation des montants côté Cloud Function). Migration des baux existants : script one-shot Admin SDK **ou** dérivation à la lecture (lazy). **Point de décision architecte.**
- **Régularisation** : `lib/features/charge_regularization/**` (FEAT-029) doit ne régulariser que le récupérable. Vérifier `charge_regularization_balance` (calcul) + le renderer PDF.
- **Formulaire** : `LeaseFormPage` / `LeaseEditPage` (Flutter) — deux champs au lieu d'un. Feature partagée web + mobile → tester les deux form factors.
- **Rétrocompat** : partout où `chargesAmountCents` est lu (quittance, dashboard, éventuels calculs), garantir que le total reste correct.

## Dépendances

- FEAT-005 (CRUD baux) ✅.
- FEAT-029 (régularisation annuelle) ✅ — consommateur direct.
- FEAT-014 Phase 3 (champs bail enrichis) ✅.

## Synergie mobile (FEAT-024)

Neutre à légèrement positif : évolution d'un formulaire de bail déjà partagé web + mobile, aucun écran mobile-spécifique à créer. ⚠️ Comme ça touche un formulaire partagé, tester sur les deux form factors avant merge si FEAT-024 est déjà avancée.

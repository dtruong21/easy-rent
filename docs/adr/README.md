# Architecture Decision Records

Décisions structurantes de Baillan, format court (Contexte / Décision /
Conséquences / Alternatives). Numérotation séquentielle, sans lacune.

| N° | Sujet | Statut |
|---|---|---|
| [0001](0001-suppression-blocking-trigger-handlenewuser.md) | Suppression du blocking trigger `handleNewUser` | accepté |
| [0002](0002-monetisation-baillan-pro-revenuecat.md) | Monétisation Baillan Pro : RevenueCat (IAP mobile + Stripe web) | accepté (amendé 2026-07-20) |
| [0003](0003-firestore-prod-staging-isolation.md) | Isolation Firestore prod/staging : base nommée `dev` + routage par Origin | proposé |

## Convention

- Fichier : `NNNN-slug-court.md`, N sur 4 chiffres, slug en minuscules.
- Statuts : `proposé` → `accepté` → (`déprécié` par ADR ultérieur | `remplacé par NNNN`).
- Un ADR ne se réécrit pas : on l'amende en fin de fichier (voir 0002) ou on
  en crée un nouveau qui le remplace.
- Longueur cible : < 350 lignes. Si l'ADR déborde, sortir les détails
  d'implémentation dans `docs/plans/`.

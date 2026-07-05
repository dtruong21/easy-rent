# FEAT-031 — Rappels automatiques de paiement

> **Statut** : 📋 Spec'd (2026-07-05) — priorisé #1 RICE (score 50), TOP 3 validé utilisateur.
> **Effort estimé** : S (~2j). **Dépend de** : FEAT-028 (détection retards), FEAT-019 (Cloud Functions).
> **Priorisation parente** : voir [`../BACKLOG.md`](../BACKLOG.md) (section « Priorisation Post-MVP P1 »).

## Contexte

FEAT-028 a livré la détection des retards de paiement (`lib/features/leases/domain/lease_lateness.dart`, règle `isLeaseLate()`) et l'affichage (KPI dashboard + pastilles « En retard »). Mais le bailleur doit encore consulter son dashboard pour savoir qu'un loyer est en retard. FEAT-031 **automatise la relance** : une Cloud Function planifiée détecte les retards et envoie un email de relance au locataire, sans action du bailleur.

## User story

**En tant que** bailleur,
**je veux** que mon locataire soit relancé automatiquement quand un loyer n'est pas payé à l'échéance,
**afin de** ne pas avoir à vérifier manuellement mon dashboard chaque mois et relancer sans effort.

## Périmètre

### Inclus (V1)
- Cloud Function **planifiée** (scheduled, quotidienne) qui détecte les baux en retard.
- Détection via la logique `isLeaseLate()` (réutilisée de FEAT-028).
- Envoi d'un **email de relance** au locataire (extension Firebase **Trigger Email**, déjà introduite en FEAT-025 V2 pour `support_requests`).
- **Anti-doublon** : jamais deux relances pour la même échéance.
- Notification / copie au bailleur (à valider par l'architecte).

### Exclus (hors V1)
- Mise en demeure formelle (acte juridique — à ne PAS confondre avec une relance informative).
- Personnalisation du texte de relance par le bailleur (V2).
- Relances configurables (fréquence, délai) — délai de grâce hérité de FEAT-028 par défaut.
- Notifications push (couvertes par FEAT-038, backlog).

## Acceptance criteria

1. **Given** un bail actif avec un paiement en retard (`isLeaseLate()` vrai) **When** la Cloud Function planifiée s'exécute **Then** un email de relance est envoyé à l'adresse du locataire et un marqueur anti-doublon est posé.
2. **Given** un locataire déjà relancé pour cette échéance **When** la fonction s'exécute à nouveau **Then** aucun second email n'est envoyé pour la même période.
3. **Given** un bail à jour de ses paiements **When** la fonction s'exécute **Then** aucun email n'est envoyé.
4. **Given** un locataire sans adresse email renseignée **When** un retard est détecté **Then** l'envoi n'échoue pas silencieusement — l'anomalie est loguée (et idéalement remontée au bailleur).
5. **Given** l'email de relance **Then** il contient a minima : période concernée, montant dû, identité du bien/bailleur, et une formulation distinguant relance amiable ≠ mise en demeure.

## Contraintes légales / conformité

- Email = communication bailleur ↔ locataire. Respecter les mentions standard (identité de l'expéditeur / responsable de traitement — cf. [`../LEGAL.md`](../LEGAL.md)).
- **Ne pas** présenter la relance comme une mise en demeure (qui exige LRAR / acte formel). Wording prudent.
- RGPD : l'email du locataire est déjà collecté pour la relation locative — pas de nouvelle base légale requise, mais pas de réutilisation hors finalité.

## Pistes techniques (à valider / affiner par l'architecte)

- **Détecteur** : réutiliser la règle `isLeaseLate()`. ⚠️ Elle est aujourd'hui côté Dart/client ; la CF est en TypeScript/Deno → soit porter la règle en TS (risque de divergence), soit définir un contrat commun. **Point de décision architecte.**
- **Scheduled CF** : suivre le pattern existant `cleanupExpiredAnon` (FEAT-019).
- **Email** : extension Firebase **Trigger Email** (déjà évoquée FEAT-025 V2). Vérifier qu'elle est provisionnée / à provisionner.
- **Anti-doublon** : probable champ `lastReminderSentAt` (ou map par période) sur `leases`. `leases` est CF-exclusive → écriture via Admin SDK depuis la CF. Impact schéma mineur + éventuel index.
- **Pas de nouvelle collection** a priori (lecture `leases` + `payments` existants).

## Dépendances

- FEAT-028 (détection retards) ✅ livré.
- FEAT-019 (Cloud Functions infra) ✅ livré.
- Extension Trigger Email (à confirmer provisionnée).

## Synergie mobile (FEAT-024)

Neutre — feature 100 % backend (Cloud Function + email), aucun écran à construire, zéro conflit avec le chantier navigation/formulaires mobile de la semaine.

# Routes — leases

> Source d'état — leases (baux, chargeMode, charge_regularization). Maintenu par state-keeper.

## Baux (shell branche 3, FEAT-005, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes deep-link |
|---|---|---|---|
| `/leases` | LeasesListPage | read | drill-down `?filter=active\|renewable\|late` |
| `/leases/new` | LeaseFormPage | write | créer |
| `/leases/:id` | LeaseDetailPage | read | `id`=UUID ; `?action=regularize` (query) auto-ouvre dialog régularisation (FEAT-030, pas de subroute) — **gate Pro appliqué aussi sur ce deep-link** (PR #120) |
| `/leases/:id/edit` | LeaseEditPage | write | `id`=UUID ; FEAT-036 : `chargesAmountCents` + `nonRecoverableChargesCents` |

## Relance de paiement assistée (FEAT-031 V1)

Bouton « Relancer le locataire » visible sur la fiche bail **si le bail est en retard** (`isLate`, FEAT-028). Lance le choix de canal (si plusieurs disponibles, bottom sheet), puis ouvre le client mail/SMS/WhatsApp du propriétaire (via `launchUrl`), pré-rempli avec un message amiable détaillé :

- **Canaux** : email (`mailto:`), SMS (`sms:`), WhatsApp (`https://wa.me/…`) — WhatsApp FR-numbers seulement
- **Message** : période due + montant (loyers + charges) + identité propriétaire/bien, mention explicite « relance amiable, pas une mise en demeure »
- **Implémentation** : 100 % client, zéro backend (pas de Cloud Function, pas d'appel réseau, pas de secret)
  - Fichiers : `payment_reminder_message.dart` (calcul message), `payment_reminder_channel.dart` (enum canaux), `payment_reminder_button.dart` (UI du bouton), `phone_uri.dart` (URI sms:/wa.me), et public `leaseCurrentDueMonth` dans `lease_lateness.dart`
- **V2 (non construit)** : automatisation cron serveur (nécessite enabler email — Resend/Trigger Email — pas encore en place)

**FEAT** : FEAT-031 (V1 = assistée client).

## Régularisation des charges — double gate (PR #120)

Ordre de précédence **volontaire**, à ne pas inverser :

1. **Gate LÉGAL d'abord** : bail au forfait → message d'inapplicabilité (`Lease.canRegularizeCharges` = `effectiveChargeMode == provisions`, FEAT-042). Un compte free sur un bail au forfait voit le message légal, **pas** un upsell — il serait trompeur de vendre une fonction que la loi n'autorise pas sur ce bail.
2. **Gate PRO ensuite** : réservé au palier `paid`. Gate **client uniquement** (calcul + PDF 100 % côté client : restriction produit, pas frontière de sécurité — rien à protéger côté serveur).
3. **Fail-closed** pendant le chargement du tier (pas de flash du bouton). Clé l10n `chargeRegularizationProOnly` (FR + EN).

**FEATs** : FEAT-005 (baux, 4 routes), FEAT-042 (chargeMode), FEAT-044 (gate Pro). Sous-routes paiements/quittances (`/leases/:id/payments…`, `/leases/:id/receipts`) → shard **payments-receipts**.

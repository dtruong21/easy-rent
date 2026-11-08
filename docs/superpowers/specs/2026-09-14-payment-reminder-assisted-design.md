# FEAT-031 V1 — Relance de paiement assistée (client-side) — Design

> **Statut** : Design validé (brainstorm 2026-09-14). Prêt pour `writing-plans`.
> **Feature** : FEAT-031 « Rappels automatiques de paiement » — **V1 redéfinie** en relance *assistée* (voir Décision d'architecture).
> **Domaine** : leases (fiche bail) + tenants (contact).
> **Dépend de** : FEAT-028 (détection retards `isLeaseLate`) ✅, FEAT-006 (paiements) ✅, `url_launcher` (déjà utilisé pour le partage des quittances) ✅.

## Problème

FEAT-028 détecte et affiche les retards (KPI dashboard, pastilles « En retard », statut fiche bail), mais le bailleur doit **rédiger et envoyer lui-même** chaque relance. Friction récurrente à chaque impayé.

## Décision d'architecture (validée 2026-09-14)

Le cadrage initial de FEAT-031 supposait une **Cloud Function planifiée** envoyant un email « au nom de Baillan » via une infra email serveur (Resend / extension Trigger Email). Après analyse :

- **Aucune infra email serveur n'existe** (`RESEND_API_KEY` supprimé en FEAT-008 ; zéro extension installée sur le projet). La monter impose un compte fournisseur, un secret, la vérification DNS de `baillan.com` (SPF/DKIM) — proche des prérequis de lancement.
- Un envoi automatique « au nom de Baillan » soulève l'**identité expéditeur** et la délivrabilité — prématuré avant lancement.

**V1 retenue : relance *assistée* 100 % côté client, zéro backend.** Le bailleur déclenche la relance en un geste ; le message part de **sa propre** messagerie / téléphone (email, SMS ou WhatsApp), pré-rempli. Réutilise exactement le patron `mailto:`/`launchUrl` déjà en production pour le partage des quittances.

Avantages : livrable immédiatement, non gaté, **0 €**, aucun secret/DNS, et juridiquement plus sain (la relance émane du bailleur, pas d'un tiers). L'automatisation serveur (cron + email infra) reste possible en **V2**, post-lancement.

## Périmètre

### Inclus (V1)
- Sur la **fiche bail**, quand le bail est en retard (`isLate`, dérivé FEAT-028) : action **« Relancer le locataire »**.
- Canaux : **email** toujours (`mailto:`) ; **SMS** (`sms:`) et **WhatsApp** (`https://wa.me/…`) proposés **uniquement si** le locataire a un `phone` renseigné.
- Sélecteur de canal (bottom sheet) quand plusieurs canaux sont disponibles ; ouverture directe si un seul (email seul).
- **Message pré-rempli** (fonction pure, testable) : salutation, adresse du bien, période concernée (mois dû courant), montant dû (loyer + charges), signature du bailleur, et formulation de **relance amiable — explicitement PAS une mise en demeure**.
- i18n FR/EN.

### Exclus (V1 — reportés)
- Cloud Function planifiée / envoi automatique (**V2**, nécessite l'enabler email serveur).
- Tracking d'envoi / anti-doublon persistant (`lastReminderSentAt`) — **V2** (aucune écriture Firestore en V1).
- Raccourci « Relancer » depuis la zone dashboard « À traiter » — **V2**.
- Mise en demeure formelle (acte juridique — hors sujet, à ne jamais confondre avec une relance).
- Personnalisation du texte par le bailleur — V2.
- Numéros non-FR robustes pour WhatsApp (V1 : normalisation FR uniquement, cf. Composants).

## Composants

### 1. Message de relance (pure) — `lib/features/leases/domain/payment_reminder_message.dart`

Fonction pure `buildPaymentReminderMessage({...}) → PaymentReminderMessage({subject, body})`, calquée sur `ChargeRegularizationSharePayloadBuilder` / le payload des quittances.

- **Entrées** : `tenantFirstName`, `landlordFullName`, `propertyAddress`, `dueMonthLabel` (ex. « septembre 2026 »), `amountDueCents`.
- **Sortie** : `subject` (ex. « Rappel — loyer de septembre 2026 ») et `body` :
  - salutation `Bonjour <prénom>,`
  - rappel que le loyer de `<dueMonthLabel>` pour le logement `<adresse>` d'un montant de `<montant formaté 1 234,56 €>` n'apparaît pas comme réglé ;
  - **phrase explicite** : « Ceci est une **relance amiable** et ne constitue pas une mise en demeure. » ;
  - invitation à régulariser / à signaler si le paiement a déjà été effectué ;
  - signature `<landlordFullName>` + `Émis via Baillan.`
- Montant formaté via `MoneyFormat.formatEurosFromCents`. `amountDueCents = lease.rentAmountCents + lease.totalChargesCents`.
- **Période concernée** : le « mois dû courant » réutilise la logique de retard FEAT-028 (`lib/features/leases/domain/lease_lateness.dart`). On expose depuis ce fichier une fonction pure donnant le mois dû courant d'un bail (année+mois) — à formatter en français via l'utilitaire de date existant (`FrenchDate`/`frenchMonthYear`). ⚠️ Normalisation date-civile-locale (`leaseLocalDate`) déjà en place — aucune régression de fuseau (cf. bug #181).

### 2. Normalisation téléphone (pure) — `lib/core/utils/phone_uri.dart`

- `smsUri(phone, body) → Uri` : `sms:` avec le numéro tel quel (nettoyé des espaces) + `?body=`.
- `whatsAppUri(phone, text) → Uri?` : normalise un numéro **FR** en E.164 sans `+` (`06…`/`+336…`/`0033…` → `336…`) et construit `https://wa.me/<num>?text=…`. Retourne `null` si la normalisation FR échoue (numéro non reconnu) → l'appelant masque WhatsApp.
- Purement testable, aucune dépendance.

### 3. Lancement des canaux — `lib/features/leases/application/payment_reminder_launcher.dart`

- Contrôleur/service fin qui, pour un canal choisi, construit l'`Uri` (mailto/sms/wa.me) à partir du message + contact et appelle `launchUrl(uri, mode: LaunchMode.externalApplication)` (même usage que `share_receipt_controller.dart`).
- mailto : `Uri(scheme: 'mailto', path: tenantEmail, queryParameters: {'subject':…, 'body':…})`.
- Gestion d'échec : si `launchUrl` échoue → SnackBar d'erreur (clé i18n dédiée), pattern identique aux quittances.

### 4. UI — `lib/features/leases/presentation/widgets/payment_reminder_button.dart`

- Widget monté sur la fiche bail (`lease_detail_page.dart`), visible **seulement si `isLate`**.
- Au tap : calcule les canaux disponibles (email toujours ; SMS/WhatsApp si `phone` non vide et — pour WhatsApp — si `whatsAppUri` ≠ null). Un seul canal → lance directement ; plusieurs → bottom sheet de sélection.
- Le message est construit une fois (builder pur) et réutilisé quel que soit le canal.

## Données disponibles (vérifié)

- `Tenant.email` (requis), `Tenant.phone` (optionnel) — `lib/features/tenants/domain/tenant.dart`.
- `Lease.rentAmountCents`, `Lease.totalChargesCents` — fiche bail.
- `isLate` déjà calculé dans `lease_detail_page.dart` (via `leasesListProvider`).
- `launchUrl` + patron `mailto:` déjà éprouvés (`share_receipt_controller.dart`).

## Gestion d'erreur

- `launchUrl` échoue (aucune app mail/SMS) → SnackBar i18n, aucun crash.
- Locataire sans email **impossible** (email requis à la création) → le canal email est toujours offert.
- `phone` absent → SMS/WhatsApp masqués, email seul.
- WhatsApp sur numéro non-FR → option masquée (normalisation `null`).

## i18n

Clés FR + EN (`@description` sur le template EN) : libellé bouton « Relancer le locataire », titres/labels du sélecteur de canal (Email/SMS/WhatsApp), sujet + corps du message (avec placeholders), erreur d'ouverture. Parité imposée par `test/l10n/arb_parity_test.dart`. `flutter gen-l10n`.

> ⚠️ Le **corps** du message part dans une URL (`mailto`/`sms`/`wa.me`) → encoder correctement (Uri s'en charge via `queryParameters`). Le texte localisé peut contenir des sauts de ligne (`\n`).

## Tests

- **Unit (pur)** : `buildPaymentReminderMessage` (période, montant formaté, présence de la mention « relance amiable / pas une mise en demeure », prénom/signature) ; `phone_uri` (`smsUri`, `whatsAppUri` : `06…`→`336…`, `+336…`→`336…`, numéro non-FR → `null`) ; la fonction « mois dû courant » exposée depuis `lease_lateness.dart` (invariance fuseau, réutilise les cas FEAT-028).
- **Widget** : `payment_reminder_button` — masqué si non `isLate` ; email seul quand `phone` vide (pas de bottom sheet) ; email+SMS+WhatsApp quand `phone` FR présent ; WhatsApp masqué sur numéro non-FR. (Le `launchUrl` réel est mocké/non exécuté — on vérifie l'`Uri` construit ou l'appel, pas l'ouverture système.)
- **i18n** : `arb_parity_test` vert.

## Definition of Done (docs d'état)

`state-keeper` ciblé : `docs/state/routes/leases.md` (bouton relance fiche bail), `FEATURES.md` (FEAT-031 → ✅ done V1, préciser « relance assistée client-side ; automatisation cron = V2 »), `CHANGELOG.md`. Aucune Rules / index / functions touchés (feature 100 % client) — rien à déployer côté backend.

## Hors scope (V2)

- Enabler email serveur (Resend/CF) + Cloud Function planifiée d'envoi automatique.
- Anti-doublon persistant (`lastReminderSentAt` sur `leases`, CF-exclusive).
- Raccourci relance depuis le dashboard « À traiter ».
- Personnalisation du texte, numéros internationaux (WhatsApp non-FR), notifications push (FEAT-038).

## Légal / conformité

- **Relance amiable ≠ mise en demeure** : la mention explicite dans le corps est obligatoire (une mise en demeure exige LRAR / acte formel — hors périmètre).
- La relance émane du **bailleur** (sa messagerie/son numéro) → identité expéditeur correcte, pas d'envoi « au nom de Baillan ».
- RGPD : email/téléphone du locataire déjà collectés pour la relation locative — pas de nouvelle base légale, pas de réutilisation hors finalité (aucune donnée ne quitte l'appareil vers un tiers ; `launchUrl` ouvre les apps natives du bailleur).
- Format montants `1 234,56 €`, dates/mois en français.

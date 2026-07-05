# Plan — [FEAT-031] Rappels automatiques de paiement

> **Statut** : Plan d'architecture (2026-07-05). Effort estimé : **S+ (~2,5 j)** dont ~0,5 j de provisioning/config infra email (première fois dans le projet).
> **Stack** : Firebase — Firestore + Cloud Functions (TypeScript/Node 20) + extension Trigger Email. **PAS Supabase.**
> **Dépend de** : FEAT-028 (règle `isLeaseLate`) ✅, FEAT-019 (infra CF) ✅.

## Summary

Une Cloud Function **planifiée quotidienne** (`sendPaymentReminders`) scanne tous les baux actifs cross-landlord via Admin SDK, applique la règle de retard (port TypeScript de `isLeaseLate`), et pour chaque bail en retard non encore relancé pour la période due, écrit un document dans la collection `mail` (déclencheur de l'extension **Trigger Email**, à provisionner). L'anti-doublon repose sur un nouveau champ **`lastReminderPeriod`** (string `YYYY-MM`) sur `leases`, écrit par la CF. L'email est une **relance amiable** (jamais une mise en demeure) avec mentions légales (identité bailleur émetteur, lien confidentialité). Le bailleur peut être mis en copie (décision à trancher).

**Découvertes clés lors de l'analyse** (écarts avec la doc d'état — à corriger dans `state/` après implémentation) :

1. **Format de stockage Firestore = camelCase**, pas le snake_case des modèles Dart. `SCHEMA.md` documente des noms Postgres périmés (`landlord_id`, `status: ongoing/upcoming/ended`). Le **vrai** contrat, confirmé dans `functions/src/callable/lease_payment.ts`, est : `landlordId`, `propertyId`, `tenantId`, `rentAmountCents`, `chargesAmountCents`, `startDate` (Timestamp), `paymentDay` (int), `status ∈ {active, terminated, archived}`, `deletedAt`. Les paiements : `leaseId`, `periodStart`/`periodEnd`/`paidAt` (Timestamp), `landlordId`, `deletedAt`.
2. **Les leases sont déjà dénormalisés** avec `tenantEmail`, `tenantFirstName`, `tenantLastName`, `propertyName`, `propertyAddress` (snapshot posé par `createLease`). La CF de rappel **n'a donc PAS besoin de join** `tenants`/`properties` — mais ce snapshot peut être **périmé** (email modifié après création du bail). Cf. Cas limites.
3. **Aucune infra email serveur n'existe** aujourd'hui. Les quittances (FEAT-008) utilisent le **Web Share API côté client**, pas d'email transactionnel. L'extension Trigger Email a été « évoquée » en FEAT-025 mais **n'a jamais été installée** (aucun dossier `extensions/`, aucune config dans `firebase.json`). FEAT-031 est la **première** capacité d'envoi email automatisé du produit → provisioning infra à prévoir.

---

## a) Modèle de données

### Impact schéma `leases` (CF-exclusive)

Un seul champ ajouté, écrit uniquement par la CF via Admin SDK (les rules `leases` interdisent déjà tout write client) :

| Champ | Type | Valeur | Écrit par |
|---|---|---|---|
| `lastReminderPeriod` | string? | `YYYY-MM` de la dernière échéance relancée (ex. `2026-06`) | CF `sendPaymentReminders` |

**Pourquoi une string `YYYY-MM` et pas un `Timestamp` `lastReminderSentAt`** :

- L'anti-doublon doit être **par échéance**, pas par date d'envoi. La question n'est pas « quand ai-je relancé ? » mais « ai-je déjà relancé POUR le mois dû courant ? ». Un `Timestamp` de dernier envoi ne répond pas à ça sans recalcul fragile.
- `isLeaseLate` (port TS) expose déjà le « mois dû courant » (`_currentDueMonth` → `{year, month}`). On le sérialise en `YYYY-MM`. L'anti-doublon devient une **comparaison d'égalité de string** triviale et idempotente : `if (lease.lastReminderPeriod === currentDuePeriod) skip`.
- Gère nativement le cas « plusieurs mois en retard » : on ne relance que sur le **mois dû le plus récent** (celui que retourne `_currentDueMonth`), et une fois relancé pour `2026-06`, le passage à `2026-07` (nouveau mois dû) redéclenchera une relance — comportement voulu (une relance par échéance).

**Alternative rejetée — map/sous-collection `reminders` par période** : suivre `{ '2026-05': ts, '2026-06': ts, ... }` permettrait un historique complet et des relances multiples par période (J+5, J+15…). Rejeté en V1 : la story exclut les relances configurables/multiples (périmètre §Exclus), et une string suffit pour l'anti-doublon « jamais deux relances pour la même échéance » (AC #2). La map/sous-collection est la voie d'extension V2 propre si on ajoute des relances échelonnées.

**Migration de données** : aucune. `lastReminderPeriod` absent ⇒ traité comme « jamais relancé » (`undefined !== '2026-06'` ⇒ vrai). Pas de backfill.

### Index Firestore (`firestore.indexes.json`)

La CF fait une **query collection cross-landlord** : « tous les baux actifs, non supprimés ». Filtre :

```
collection("leases").where("deletedAt", "==", null).where("status", "==", "active")
```

Aucun index existant ne couvre exactement `(deletedAt ==, status ==)` **sans** troisième champ de tri obligatoire (les index leases actuels sont tous `landlordId`- ou `startDate`/`endDate`-préfixés). Deux options :

- **Option A (recommandée)** : ajouter un index composite minimal `leases: (deletedAt ASC, status ASC)`. Query stable, paginée par `startAfter(docId)`.
- **Option B** : réutiliser l'index existant `deletedAt, landlordId, status, startDate` en itérant landlord par landlord (query par landlord). Rejeté : N queries au lieu d'1, complexité inutile pour un cron nocturne (une seule query paginée suffit largement au volume MVP).

> ⚠️ Piège `== null` documenté dans `SCHEMA.md` (« isEqualTo: null »). Firestore **refuse** `where("deletedAt", "==", null)` **sans** index composite couvrant le champ. L'index Option A résout ce point. À valider en emulator avant deploy.

Index à ajouter :
```json
{
  "collectionGroup": "leases",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deletedAt", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" }
  ]
}
```

### RLS / rules

**Résumé RLS en un paragraphe** (garde-fou projet) : Le champ `lastReminderPeriod` n'est écrit **que** par la CF via Admin SDK, qui bypasse les rules ; côté client, `leases` est déjà totalement verrouillée en écriture (`allow create, update, delete: if false`) et lisible seulement par son propriétaire actif (`isOwner(landlordId) && isActive(resource)`) — l'ajout du champ n'ouvre donc **aucune** surface. La collection déclencheur `mail` (Trigger Email) n'est **jamais** exposée au client : le catch-all final de `firestore.rules` (`match /{document=**} { allow read, write: if false }`) la bloque déjà par défaut, et seule la CF (Admin SDK) y écrit.

**Aucune modification de `firestore.rules` strictement nécessaire.** Optionnel mais recommandé pour la lisibilité/défense-en-profondeur explicite : ajouter un bloc commenté `match /mail/{id} { allow read, write: if false; }` documentant que la collection Trigger Email est CF-exclusive (sinon elle reste implicitement couverte par le catch-all — c'est suffisant).

---

## b) Backend — Cloud Function planifiée

### `sendPaymentReminders` (scheduled)

- **Type** : `onSchedule` (Cloud Scheduler), calqué sur `cleanupExpiredAnon` (`functions/src/scheduled/cleanup_expired_anon.ts`).
- **Fréquence proposée** : **quotidienne à 08:00 Europe/Paris** (`schedule: "0 8 * * *"`, `timeZone: "Europe/Paris"`, `region: "europe-west1"`). Matin ouvrable = email lu dans la journée (vs 03:00 comme le cleanup, où un email de relance arriverait la nuit). Fréquence à trancher (voir Décisions).
- **Fichier** : `functions/src/scheduled/send_payment_reminders.ts`.

**Algorithme** :
1. `now = Timestamp.now()`.
2. Query paginée `leases where deletedAt == null && status == "active"`, batch de `BATCH_SIZE = 200` via `startAfter` (borne coût/timeout ; le cron peut boucler sur plusieurs pages dans un même run).
3. Pour chaque lease :
   a. Calculer le **mois dû courant** via le port TS de `isLeaseLate` — signature qui retourne le `YYYY-MM` dû (ou `null` si pas de mois dû). Injecter `now`.
   b. Si `dueMonth == null` → à jour / trop récent → **skip** (AC #3).
   c. Charger les paiements du bail : `payments where leaseId == <id> && deletedAt == null` (index existant `landlordId, leaseId, deletedAt, periodStart` — mais ici query cross-landlord par `leaseId` : ajouter au besoin un index `leaseId, deletedAt` **ou** filtrer aussi `landlordId` connu depuis le lease pour réutiliser l'index existant → **préférer réutiliser** `landlordId + leaseId + deletedAt`).
   d. Appliquer la couverture (`_paymentCoversMonth`) : si un paiement couvre `dueMonth` → **skip** (le bail n'est pas réellement en retard).
   e. Si en retard **et** `lease.lastReminderPeriod === dueMonthStr` → **skip** (anti-doublon, AC #2).
   f. Sinon : bail en retard non relancé pour cette période →
      - Résoudre l'email destinataire : `lease.tenantEmail` (dénormalisé). Si vide/absent/invalide → **ne PAS écrire de mail**, **loguer** l'anomalie (`logger.warn` avec `leaseId`, `landlordId`) et (option) notifier le bailleur (voir Décisions). AC #4.
      - **Transaction / write atomique** : dans une même opération, (1) `set` du document `mail/{autoId}` (payload Trigger Email) **et** (2) `update` `leases/{id}.lastReminderPeriod = dueMonthStr`. Idéalement un `batch` pour lier les deux écritures → si le marqueur échoue, on n'a pas de mail « fantôme » sans marqueur (double envoi au prochain run) ; si le mail échoue, pas de marqueur posé (retry au prochain run). **Ordre** : écrire le marqueur **puis** le mail dans le batch commit — en cas d'échec du commit, ni l'un ni l'autre. (Trigger Email consomme le doc `mail` de façon asynchrone hors transaction ; le risque résiduel « mail écrit mais delivery KO » est géré par l'extension elle-même via son champ `delivery`.)
4. Logger le récap : `{ scanned, late, remindersSent, skippedNoEmail, skippedAlreadySent }`.

**Idempotence** : garantie par `lastReminderPeriod`. Deux runs le même jour (ou un retry Scheduler) ne produisent qu'un seul mail par échéance. Le `mail/{autoId}` utilise un docId auto (pas d'idempotence sur le doc mail lui-même — l'idempotence est portée par le marqueur lease, vérifié AVANT l'écriture).

**Multi-landlord** : la query est globale (tous les baux actifs), pas de boucle par landlord. Le `landlordId` de chaque lease sert uniquement à (a) réutiliser l'index paiements et (b) résoudre l'identité bailleur pour les mentions légales (fetch `landlords/{landlordId}` — `fullName`, `email` — mis en cache mémoire dans le run pour éviter les lectures répétées si un bailleur a plusieurs baux en retard).

**Garde-fous coût** : `setGlobalOptions` fixe déjà `maxInstances: 10`. Le cron est mono-instance (déclenchement unique). Volume MVP faible → une exécution < quelques secondes. `BATCH_SIZE` borne la mémoire.

---

## Réutilisation de `isLeaseLate()` — port TypeScript (recommandé)

`isLeaseLate` vit aujourd'hui en Dart (`lib/features/leases/domain/lease_lateness.dart`), fonction **pure** et déjà bien documentée (règle métier tranchée produit : grâce 5 j, pas de prorata 1er mois, clamp mois courts, couverture par recouvrement d'intervalle).

**Options évaluées** :

| Option | Description | Verdict |
|---|---|---|
| **A. Port TS testé** (recommandé) | Réécrire la logique pure en TS dans `functions/src/domain/lease_lateness.ts`, avec **vitest** portant les MÊMES cas que le test Dart. Exposer une fonction qui retourne le `YYYY-MM` dû (ou `null`) plutôt qu'un simple bool, pour servir l'anti-doublon. | ✅ **Retenu** |
| B. Exécuter le Dart côté serveur | Dart AOT dans une CF / Cloud Run séparé. | ❌ Rejeté — le codebase functions est 100 % TS/Node 20, aucun runtime Dart serveur, complexité et coûts démesurés. |
| C. Contrat JSON partagé / source unique | Générer la règle depuis une spec commune. | ❌ Rejeté — sur-ingénierie pour une fonction de ~60 lignes ; pas d'outillage de partage Dart↔TS dans le projet. |

**Le port TS est la seule option pragmatique, mais introduit un risque de divergence réel** (deux implémentations d'une règle métier légale/financière). Mitigations **obligatoires** :

1. **Test de parité** : le fichier `functions/src/__tests__/lease_lateness.test.ts` doit rejouer **exactement** les cas du test Dart (`test/.../lease_lateness_test.dart`) — mêmes dates d'entrée, mêmes attendus. Tout cas ajouté d'un côté doit l'être de l'autre.
2. **Documentation croisée** : un commentaire d'en-tête dans **les deux** fichiers pointant l'un vers l'autre + la ligne « toute modification de la règle doit être répercutée et re-testée des deux côtés ».
3. **Piège fuseau horaire — CRITIQUE** : le Dart applique `.toLocal()` avant de tronquer les dates (cf. `_dateOnly`, longue doc dans le fichier : neutralise le décalage UTC→Europe/Paris). Côté CF, les dates sont des **`Timestamp` Firestore** ⇒ `timestamp.toDate()` donne un `Date` JS dont le fuseau dépend du **TZ du process** (les CF tournent en **UTC** par défaut). **Il faut convertir explicitement en Europe/Paris** (jour civil FR) avant de tronquer, sinon un bail démarrant le 16 avec `paymentDay=15` peut devenir faussement éligible dès le mois courant (exactement le bug décrit dans la doc Dart). Recommandation : forcer le calcul du « jour civil » en `Europe/Paris` via `Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', ... })` ou une lib de dates minimale, et **couvrir ce cas par un test dédié**. À défaut de lib, extraire year/month/day via `toLocaleString('fr-FR', { timeZone: 'Europe/Paris' })`. **Ne pas** ajouter de grosse dépendance date (luxon) juste pour ça sauf accord (voir Décisions).
4. **`paymentDay` hors bornes** : `createLease` contraint `paymentDay ∈ [1,28]`, mais des baux importés/migrés (pré-FEAT-019) peuvent porter d'autres valeurs. Le port TS **doit** reproduire le clamp `min(paymentDay, dernierJourDuMois)` du Dart. Couvrir `paymentDay=31` en février.

---

## c) Envoi email — extension Trigger Email

### Provisioning (à faire — n'existe pas aujourd'hui)

L'extension **`firebase/firestore-send-email`** (Trigger Email) n'est pas installée. À provisionner :

1. **Installer l'extension** (`firebase ext:install firebase/firestore-send-email` ou console), qui crée sa propre CF déclenchée sur une collection (par défaut `mail`).
2. **Backend d'envoi (SMTP)** requis par l'extension. Décision infra à trancher (voir Décisions) : SMTP transactionnel type Brevo/Sendinblue (offre FR, RGPD-friendly), Mailgun, Resend-via-SMTP, ou SMTP Gmail (déconseillé en prod — quotas/délivrabilité). **Secret SMTP** stocké **exclusivement** côté serveur : via **Secret Manager** / config d'extension, **jamais** dans le client ni committé (garde-fou `SECURITY.md`).
3. **Domaine expéditeur** : configurer SPF/DKIM sur le domaine d'envoi (délivrabilité + conformité). Adresse `From` = identité Baillan (ex. `relances@baillan.fr` ou `noreply@…`) — **pas** l'email personnel du bailleur (voir mentions légales).
4. **Paramètres extension** : `MAIL_COLLECTION=mail`, `DEFAULT_FROM`, `DEFAULT_REPLY_TO` (peut être l'email du bailleur → permet au locataire de répondre au bon interlocuteur, cf. Décisions).

> Le provisioning SMTP + DNS est la principale **inconnue de charge** (0,5 j) et **dépend d'un choix produit/infra** (quel fournisseur, quel domaine). À débloquer avec le product-owner **avant** le code CF.

### Structure du document déclencheur (`mail/{autoId}`)

Format natif de l'extension (envoi inline HTML/text ; templates Handlebars optionnels via collection `templates` — inutile en V1, on inline) :

```
{
  to: [ "<tenantEmail>" ],                    // destinataire principal
  cc: [ "<landlordEmail>" ],                  // OPTION bailleur en copie (à trancher)
  replyTo: "<landlordEmail>",                 // le locataire répond au bailleur (à trancher)
  message: {
    subject: "Rappel : loyer de <mois AAAA> — <propertyName>",
    text: "<version texte>",
    html: "<version HTML avec mentions légales>"
  }
  // + champs de traçabilité applicatifs (non lus par l'extension) :
  // leaseId, landlordId, reminderPeriod, kind: "payment_reminder"
}
```

L'extension ajoute automatiquement un champ `delivery` (state/attempts/error) au doc après tentative — utile pour l'observabilité (query des échecs de délivrance).

### Contenu du template (mentions légales)

Tons et mentions imposés par `LEGAL.md` (§Mentions email) + périmètre story (AC #5, relance amiable ≠ mise en demeure) :

- **Objet** neutre : « Rappel : loyer de {mois AAAA} ».
- **Corps** doit contenir a minima (AC #5) :
  - **Période** concernée (ex. « loyer de juin 2026 »).
  - **Montant dû** (loyer + charges), formaté FR : `1 234,56 €` (espace insécable, virgule, € à droite — cf. `LEGAL.md`).
  - **Identité du bien** (`propertyName` / `propertyAddress`) et **du bailleur émetteur** (`landlord.fullName`) — obligation « nom du responsable de traitement / coordonnées de l'émetteur » (`LEGAL.md`).
  - **Nom de l'app** (Baillan) + **lien vers la politique de confidentialité** (`/privacy`).
- **Wording prudent — NON négociable** : formuler comme un **rappel amiable / courtoisie** (« Sauf erreur ou paiement récent de votre part, nous n'avons pas enregistré le règlement du loyer de… »). **Interdits** : « mise en demeure », « injonction », mention de pénalités/LRAR, ton comminatoire. La mise en demeure est un acte formel (LRAR) explicitement **hors périmètre** (§Exclus).
- **Désabonnement** : `LEGAL.md` exige un lien de désabonnement pour les emails **non transactionnels**. Statut de la relance à trancher (voir Décisions) : soit on la traite comme quasi-transactionnelle (relation contractuelle locative → base légale = exécution du contrat, pas de consentement marketing), soit on ajoute une mention de contact/opposition. **Recommandation** : mention « Vous recevez cet email dans le cadre de votre contrat de location. Pour toute question, contactez {bailleur} » plutôt qu'un lien de désinscription (un locataire ne peut pas se désabonner d'une obligation contractuelle) — **à valider juridiquement**.
- **Format dates** : `DD/MM/YYYY` (locale fr_FR), mois en toutes lettres pour la période (« juin 2026 »).

Le rendu HTML/texte est construit **dans la CF** (helper `buildReminderEmail(...)` pur et testé) puis posé dans `message`.

---

## d) Flutter changes

**Aucun écran, aucun provider, aucune route.** Feature 100 % backend (confirme la note « Synergie mobile » de la story : neutre, zéro conflit avec le chantier nav/formulaires mobile).

Deux impacts Flutter **mineurs et optionnels** :

- **Modèle `Lease` (Dart)** : ajouter `lastReminderPeriod` (`@JsonKey(name: 'last_reminder_period') String? lastReminderPeriod`) **uniquement si** on veut afficher « Relancé le… » dans l'UI (hors périmètre V1). **Non requis** : un champ Firestore non mappé est simplement ignoré par `firestoreDocToSnakeJson` → `Lease.fromJson` (les champs inconnus n'échouent pas). **Recommandation V1 : ne pas toucher au modèle Dart.**
- **Port de règle** : le port TS **ne modifie pas** le Dart existant (`lease_lateness.dart` reste la source client). On ajoute seulement un commentaire de renvoi croisé.

---

## e) Cas limites

| Cas | Traitement |
|---|---|
| **Locataire sans email** (`tenantEmail` vide/`null`) | Ne PAS écrire de `mail` (sinon Trigger Email échoue silencieusement dans son champ `delivery`). `logger.warn({ leaseId, landlordId, reason: "no_tenant_email" })`. **Option** : incrémenter un compteur remonté au bailleur (voir Décisions). Comptabilisé `skippedNoEmail`. **Ne pose PAS** `lastReminderPeriod` → réessai chaque jour tant que l'email manque (visible dans les logs). AC #4. |
| **Email dénormalisé périmé** | `lease.tenantEmail` est un snapshot posé à `createLease` ; si le locataire a changé d'email depuis, la relance part sur l'ancienne adresse. **Mitigation V1** : documenter la limite. **Mitigation propre (option)** : re-fetch `tenants/{tenantId}.email` frais dans la CF (une lecture de plus par bail en retard — coût négligeable au volume MVP). **Recommandation : re-fetch le tenant** pour l'email (source de vérité), fallback sur `lease.tenantEmail`. |
| **Plusieurs périodes en retard** | On ne relance QUE sur le **mois dû courant** (le plus récent, retourné par `_currentDueMonth`). Pas de spam rétroactif sur tous les mois impayés. Quand le mois avance, `lastReminderPeriod` diffère → nouvelle relance sur la nouvelle échéance. |
| **Paiement partiel** | Hors scope (le montant n'est jamais vérifié — cf. doc `isLeaseLate`, « le montant n'est jamais vérifié »). Un paiement qui recouvre la période, même partiel, désactive la relance. Cohérent avec FEAT-028. |
| **Bail `terminated`/`archived`** | Filtré en amont (`status == "active"` dans la query). Jamais relancé. AC #3. |
| **Bail dans le délai de grâce (J+5)** | `_currentDueMonth` retourne `null` → skip. Pas de relance prématurée. |
| **Bailleur avec N baux en retard** | Fetch `landlords/{landlordId}` mis en cache mémoire dans le run (Map par uid) → une seule lecture par bailleur, pas N. |
| **Fuseau horaire** | Cf. §Port TS point 3 — conversion Europe/Paris obligatoire, test dédié. |
| **Bailleur soft-deleted / anonyme expiré** | Un lease actif dont le landlord a été purgé (cleanup anon) : normalement les leases sont soft-deleted par la cascade `cleanupExpiredAnon`… **à vérifier** — le cleanup actuel ne soft-delete PAS les leases des anonymes (les anonymes n'ont pas de baux, ils ont juste le simulateur). Garde-fou : la CF peut skip si `landlords/{landlordId}` est absent ou `deletedAt != null` (`logger.warn`). |

---

## f) Testing strategy

### Tests unitaires vitest — `functions/` (framework en place, cf. `finalize_anonymous_upgrade.test.ts`)

1. **`lease_lateness.test.ts`** (port TS de la règle — le plus critique) :
   - **Parité** avec le test Dart : rejouer tous les cas (grâce 5 j exacte, J+4 pas en retard / J+6 en retard, 1er mois non prorata, bail démarrant après paymentDay saute au mois suivant, clamp `paymentDay=31` février, couverture par recouvrement d'intervalle, bail non actif jamais en retard).
   - **Cas fuseau** (nouveau) : bail `startDate=16` UTC-relu, `paymentDay=15`, vérifier qu'il n'est PAS faussement en retard le mois courant.
   - Vérifier le **retour `YYYY-MM`** attendu (mapping AC #1/#2).
2. **`send_payment_reminders` — logique de sélection** (fonctions pures extraites) :
   - `shouldSendReminder(lease, payments, now)` → skip si à jour (AC #3), skip si `lastReminderPeriod == dueMonth` (AC #2), send sinon (AC #1).
   - `resolveRecipient(lease, tenant)` → email frais vs snapshot vs null (AC #4).
3. **`buildReminderEmail(...)`** :
   - Contient période, montant formaté FR (`1 234,56 €`), `propertyName`, `landlord.fullName`, lien `/privacy` (AC #5).
   - **Ne contient PAS** « mise en demeure » / « LRAR » / « pénalités » (assertion négative — garde-fou wording).
4. **Anti-doublon / idempotence** (via `firebase-functions-test` + emulator Firestore, ou mock `admin.firestore`) : deux exécutions consécutives ⇒ un seul doc `mail` par échéance, `lastReminderPeriod` posé.

### Tests Dart

- **Aucun nouveau** requis (règle Dart inchangée). Vérifier que `test/.../lease_lateness_test.dart` reste vert (référence de parité).

### QA manuel (emulator + staging)

1. Seed : bail actif + échéance dépassée > grâce, sans paiement couvrant → run cron (emulator `firebase functions:shell` ou trigger manuel) → 1 doc `mail`, `lastReminderPeriod` posé, email reçu (SMTP staging).
2. Re-run → **aucun** 2e mail (AC #2).
3. Bail à jour → aucun mail (AC #3).
4. Bail avec `tenantEmail` vide → log warn, pas de mail, pas de marqueur (AC #4).
5. Vérif contenu email (mentions légales, wording amiable) (AC #5).
6. Bascule de mois : simuler `now` au mois M+1 → nouvelle relance sur la nouvelle échéance.

### Mapping AC → tests

| AC | Test |
|---|---|
| #1 (relance + marqueur) | `shouldSendReminder` send-case + QA 1 |
| #2 (anti-doublon) | idempotence vitest + QA 2 |
| #3 (à jour → rien) | `shouldSendReminder` skip-paid + QA 3 |
| #4 (sans email → log, pas d'échec silencieux) | `resolveRecipient` null-case + QA 4 |
| #5 (contenu + wording) | `buildReminderEmail` (assertions positives + négatives) + QA 5 |

---

## g) Sécurité / RGPD

- **Firestore rules** : aucune ouverture. `leases` reste write-client interdit ; `mail` couverte par le catch-all `if false` (client ne lit/écrit jamais). CF = Admin SDK (bypass légitime). Ajout optionnel d'un `match /mail` commenté explicite.
- **Secrets** : clé/mot de passe SMTP **exclusivement** en Secret Manager / config extension côté serveur. **Jamais** de secret d'envoi email côté client (garde-fou `SECURITY.md` : jamais de `re_*`/`service_role`/secret côté client). Le client ne connaît même pas l'existence de la collection `mail`.
- **RGPD / finalité** : l'email du locataire est déjà collecté pour la **relation locative** (base légale = exécution du contrat, art. 6.1.b RGPD). La relance de loyer **rentre dans cette finalité** — pas de nouvelle base légale ni de consentement requis. **Pas de réutilisation hors finalité** (pas de marketing sur cette adresse). Journalisation minimale (logs Cloud Logging avec `leaseId`/`landlordId`, pas le contenu de l'email au-delà du nécessaire).
- **Mentions expéditeur** (`LEGAL.md`) : identité du responsable de traitement (bailleur) + coordonnées + lien confidentialité dans chaque email. `From` = domaine Baillan (pas l'email perso du bailleur, pour SPF/DKIM), `replyTo` = bailleur (à trancher) pour que la réponse aille au bon interlocuteur.
- **Anti-usurpation ton légal** : garde-fou wording (« relance amiable ») testé négativement — évite qu'un email Baillan soit pris pour un acte juridique (risque réputationnel + juridique).

---

## h) Fichiers touchés

### Créés
- `functions/src/scheduled/send_payment_reminders.ts` — la CF planifiée (query, sélection, écriture mail + marqueur).
- `functions/src/domain/lease_lateness.ts` — **port TS** de la règle (fonction pure, retourne `YYYY-MM` dû ou `null`).
- `functions/src/domain/reminder_email.ts` — `buildReminderEmail(...)` (rendu HTML/texte + mentions légales, pur).
- `functions/src/__tests__/lease_lateness.test.ts` — parité + cas fuseau.
- `functions/src/__tests__/send_payment_reminders.test.ts` — sélection + idempotence.
- `functions/src/__tests__/reminder_email.test.ts` — contenu + assertions négatives wording.

### Modifiés
- `functions/src/index.ts` — export `sendPaymentReminders` (section « Scheduled »).
- `firestore.indexes.json` — ajout index `leases: (deletedAt ASC, status ASC)` (+ éventuel `payments: (leaseId ASC, deletedAt ASC)` si on ne réutilise pas l'index landlordId-préfixé).
- `firebase.json` — bloc `extensions` si l'installation d'extension est déclarée en IaC (`{ "extensions": { "firestore-send-email": "firebase/firestore-send-email@x.y.z" } }`), OU installation via console (choix de gestion infra).
- `firestore.rules` — **optionnel** : bloc `match /mail/{id} { allow read, write: if false; }` documentaire (sinon couvert par catch-all).

### NON touchés (V1)
- `lib/**` — aucun changement (modèle `Lease` intact, pas d'UI). Port TS n'altère pas `lib/features/leases/domain/lease_lateness.dart` (ajout d'un commentaire de renvoi croisé seulement).

### Docs d'état à corriger après implémentation (dette repérée)
- `docs/state/SCHEMA.md` — noms de champs `leases`/`payments` (camelCase réel, `status ∈ {active,terminated,archived}`, champs dénormalisés `tenantEmail`/`propertyName`/etc.), ajout `lastReminderPeriod`, statut réel Trigger Email.
- `docs/state/FUNCTIONS.md` — ajout `sendPaymentReminders`.

---

## Step-by-step execution order

1. **[Décisions ci-dessous tranchées]** avec product-owner (surtout : fournisseur SMTP + domaine, bailleur en copie, statut désabonnement).
2. **Provisionner Trigger Email** : installer l'extension `firebase/firestore-send-email`, configurer SMTP (Secret Manager) + SPF/DKIM du domaine expéditeur, valider un envoi test.
3. **Port TS de la règle** (`functions/src/domain/lease_lateness.ts`) + `lease_lateness.test.ts` (parité + fuseau) → **vert avant toute autre chose** (c'est le cœur de risque).
4. **`reminder_email.ts`** + test (contenu + wording négatif).
5. **`send_payment_reminders.ts`** (query, sélection, batch mail+marqueur, logs) + `index.ts` export.
6. **Index** `firestore.indexes.json` + `firebase deploy --only firestore:indexes` (build de l'index avant le 1er run cron).
7. **Tests** vitest complets (`qa-tester`).
8. **QA emulator** (scénarios AC #1–5) puis **staging** (envoi SMTP réel sur adresse test).
9. **Review** `code-reviewer` (idempotence, gestion erreurs, coût) + `security-auditor` (secrets SMTP, RGPD finalité, wording légal, aucune fuite `mail` client).
10. **Deploy prod** (`firebase deploy --only functions`) **après confirmation utilisateur** + configuration Cloud Scheduler.
11. `state-keeper` : mettre à jour `SCHEMA.md` / `FUNCTIONS.md` (+ corriger la dette de nommage repérée).

---

## ❓ Décisions à trancher avant implémentation

1. **Fournisseur SMTP + domaine expéditeur** *(bloquant — c'est la première infra email du produit)*.
   → **Recommandation** : Brevo (Sendinblue) — fournisseur FR, RGPD-friendly, offre gratuite suffisante au volume MVP, SMTP simple compatible Trigger Email. Domaine `From` dédié (`relances@baillan.fr` ou sous-domaine `mail.baillan.fr`) avec SPF/DKIM. Secret en Secret Manager.

2. **Destinataire : locataire seul, ou bailleur en copie ?**
   → **Recommandation** : locataire en `to` + bailleur en **`replyTo`** (le locataire répond directement au bailleur), **sans `cc`** systématique en V1 (évite d'inonder le bailleur ; il consulte déjà son dashboard). Ajouter le `cc` bailleur en option V2 si demandé. À défaut, `cc` bailleur acceptable si le PO veut une trace côté bailleur.

3. **Fréquence / heure du cron.**
   → **Recommandation** : **quotidien à 08:00 Europe/Paris**. Quotidien pour réactivité (dès J+6 après échéance), heure ouvrable pour la lisibilité. (Le cron quotidien ne spamme pas grâce à l'anti-doublon `lastReminderPeriod`.)

4. **Stratégie de port de la règle `isLeaseLate`.**
   → **Recommandation** : **port TS testé** (Option A) avec test de parité obligatoire + doc croisée + test fuseau dédié. Accepter et tracer le risque de divergence (mitigé par les tests miroir). Pas de runtime Dart serveur.

5. **Champ anti-doublon : `lastReminderPeriod` (string `YYYY-MM`) sur `leases`.**
   → **Recommandation** : **oui**, string `YYYY-MM` (pas `Timestamp`, pas map). Écrit CF-only, migration nulle, index inutile pour ce champ (jamais requêté, juste lu). Extension V2 (relances échelonnées) → migrer vers sous-collection `reminders` le moment venu.

6. **Statut « transactionnel » de la relance & désabonnement (RGPD/`LEGAL.md`).**
   → **Recommandation** : traiter comme **communication contractuelle** (exécution du bail, art. 6.1.b) → pas de lien de désinscription, mais mention explicite « email envoyé dans le cadre de votre contrat de location, pour toute question contactez {bailleur} ». **À valider juridiquement** (surface au PO comme point de conformité, pas un blocage technique).

7. **Email destinataire : re-fetch `tenants.email` frais, ou snapshot `lease.tenantEmail` ?**
   → **Recommandation** : **re-fetch le tenant** (source de vérité) avec fallback sur le snapshot lease. Une lecture de plus par bail en retard, négligeable au volume MVP, évite d'envoyer sur un email périmé.

8. **Dépendance date en TS pour le fuseau Europe/Paris ?**
   → **Recommandation** : **sans nouvelle dépendance** — utiliser `Intl`/`toLocaleString('fr-FR', { timeZone: 'Europe/Paris' })` pour extraire le jour civil. Ajouter `luxon` seulement si la manipulation devient trop fragile (à décider en implémentation, ne pas pré-committer une dépendance).

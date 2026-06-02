# FEAT-008 — Envoyer une quittance par email

## User story

En tant que **propriétaire bailleur**, je veux **envoyer par email une quittance PDF à mon locataire depuis la liste des quittances d'un bail** afin de **remplir mon obligation légale de remise de quittance (loi du 6 juillet 1989, art. 21) sans manipulation manuelle de fichier**.

---

## Contexte & motivation

FEAT-007 a livré la génération et le stockage des quittances PDF dans Supabase Storage (bucket `receipts/`, privé). Le bailleur peut déjà prévisualiser et télécharger le PDF. Il lui manque le canal d'envoi direct au locataire.

En pratique, la remise de quittance en France est une obligation légale à la demande du locataire (art. 21 loi 1989). Ne pas avoir de canal d'envoi intégré force le bailleur à télécharger manuellement, ouvrir son client email, attacher le fichier — friction inutile et source d'oublis. L'envoi en un clic depuis l'interface constitue la valeur métier principale de cette feature.

La table `receipts` expose déjà `pdf_path` (chemin Storage) et la relation `lease_id → tenant_id → email`. L'Edge Function `send-receipt` consomme ces données, génère une URL signée (5 min) pour récupérer le PDF côté serveur, et transmet via l'API Resend.

---

## Personas & scénario principal

**Persona** : David, propriétaire de 3 appartements, gère tout seul sans agence.

**Scénario** : En fin de mois il génère la quittance de mai pour son locataire (FEAT-007). Il clique sur "Envoyer par email" depuis `LeaseReceiptsPage`. L'email arrive chez le locataire avec le PDF en pièce jointe. David voit ensuite l'horodatage "Envoyé le 01/06/2026" sur la quittance dans l'interface.

---

## Décisions à prendre

Les points suivants ne sont pas encore tranchés. Un **défaut raisonné** est proposé pour chacun ; à valider ou infirmer par le Product Owner avant implémentation.

### D1 — Tenant sans email : bloquer ou fallback ?

**Situation** : `tenants.email` est `NULL` ou vide (champ optionnel en FEAT-004).

**Options** :
- A) Bloquer l'envoi avec message explicite "Ajoutez l'email de votre locataire pour envoyer la quittance"
- B) Fallback : envoyer au bailleur (`landlords.email`) avec mention "Copie bailleur — aucune adresse locataire"

**Défaut recommandé** : **Option A** — bloquer avec message orientant vers la fiche locataire. L'option B masque une donnée manquante et risque de faire croire à l'utilisateur que le locataire a été notifié. Coût de mise en oeuvre identique.

### D2 — Idempotence : peut-on renvoyer la même quittance ?

**Situation** : Le bailleur clique deux fois (erreur de manipulation ou renvoi après non-réception).

**Options** :
- A) Interdit — bouton disabled si `sent_at IS NOT NULL`
- B) Autorisé avec confirmation — dialog "Déjà envoyé le JJ/MM/YYYY, envoyer à nouveau ?"
- C) Autorisé sans friction — l'envoi se fait, `sent_at` est mis à jour, `sent_to_email` conservé

**Défaut recommandé** : **Option B** — confirmation légère. Elle évite les doubles envois accidentels tout en permettant les cas légitimes (locataire n'a pas reçu). L'option A est trop restrictive, l'option C expose à des doublons silencieux.

### D3 — Reply-to : email bailleur ou no-reply ?

**Situation** : Si `reply-to = landlords.email`, le locataire peut répondre directement au bailleur — pratique mais expose l'adresse du bailleur dans l'en-tête email.

**Options** :
- A) `reply-to = landlords.email` (exposition de l'email bailleur dans l'en-tête)
- B) `reply-to = noreply@easyrent.app` ou aucun reply-to
- C) Configurable par le bailleur (checkbox "Autoriser les réponses directes")

**Défaut recommandé** : **Option B** pour le MVP — pas de reply-to. Le RGPD n'interdit pas l'option A, mais exposer l'adresse du bailleur dans l'en-tête à un tiers (locataire) sans consentement explicite est un risque de friction. La fonctionnalité peut passer en P1 avec opt-in bailleur.

### D4 — Branding et style de l'email

**Options** :
- A) Template texte pur (plain text seulement)
- B) HTML minimal (police système, pas d'image, fond blanc, quelques styles inline)
- C) HTML stylisé (logo EasyRent, couleurs M3, tableau récap montants)

**Défaut recommandé** : **Option B** — HTML minimal. La livraison et la lisibilité sur mobile sont meilleures qu'en plain text pur. L'option C nécessite un designer et sort du scope MVP.

### D5 — Rate-limit Resend saturé (free tier 3 000 emails/mois)

**Situation** : Un bailleur avec beaucoup de lots atteint la limite ou le quota mensuel est épuisé.

**Options** :
- A) Retourner une erreur 429 avec message "Quota email dépassé — réessayez le mois prochain" (aucune mise en file d'attente)
- B) Mettre en file d'attente (cron + table `email_queue`) et renvoyer dès que quota disponible
- C) Ignorer silencieusement et marquer `sent_at` quand même (INTERDIT — mensongèr)

**Défaut recommandé** : **Option A** pour le MVP — erreur explicite, pas de complexité de queue. La limite de 3 000/mois couvre ≈ 100 bailleurs avec 30 quittances chacun, suffisant pour le MVP. L'option B est une dette technique à intégrer en P1 si nécessaire.

---

## Scope

- Edge Function Deno `send-receipt` : valide ownership, récupère URL signée, télécharge PDF, construit email HTML minimal en français, envoie via Resend API, met à jour `receipts.sent_at` et `receipts.sent_to_email`
- Migration SQL : ajout de `sent_at TIMESTAMPTZ` et `sent_to_email TEXT` sur `public.receipts` et `dev.receipts`
- Flutter UI : bouton "Envoyer par email" sur `ReceiptListTile`, état "Envoyé le JJ/MM/YYYY" après succès, toast d'erreur sur échec, dialog de confirmation si renvoi (D2)
- Secrets : `RESEND_API_KEY` dans Supabase Edge Function Secrets (jamais côté client)
- Sujet email : `"Votre quittance de loyer — <mois en français> <année>"` (ex : "Votre quittance de loyer — mai 2026")
- Corps email : HTML minimal, rappel du montant total, période, nom du bailleur, PDF en pièce jointe base64
- Blocage si `is_stale = true` ou `voided_at IS NOT NULL` (quittances invalides interdites à l'envoi)

---

## Hors scope

- Envoi automatique (cron mensuel) — P1
- Envoi groupé (toutes les quittances du mois en une action) — P1
- File d'attente email (`email_queue`) — P1
- Accusé de réception (webhook Resend `email.delivered`) — P2
- Template HTML stylisé (logo, couleurs) — P2
- Envoi via autre provider (Mailgun, SendGrid) — P2
- SMS ou notification push — P2
- Re-génération du PDF à la volée si absent (si `pdf_path IS NULL`) — hors MVP (cas anormal)
- Configuration reply-to bailleur — P1 avec opt-in

---

## Acceptance criteria

**AC1 — Happy path : envoi réussi**
- **Given** une quittance valide (`is_stale = false`, `voided_at IS NULL`) avec `pdf_path` renseigné, liée à un bail dont le tenant a un email
- **When** le bailleur clique sur "Envoyer par email" et confirme si nécessaire
- **Then** l'email est envoyé via Resend au tenant (`tenants.email`) avec le PDF en pièce jointe, `receipts.sent_at` est renseigné avec l'horodatage courant, `receipts.sent_to_email` est renseigné avec l'email du tenant, et l'UI affiche "Envoyé le JJ/MM/YYYY" sur la quittance

**AC2 — Confirmation si renvoi**
- **Given** une quittance déjà envoyée (`sent_at IS NOT NULL`)
- **When** le bailleur clique à nouveau sur "Envoyer par email"
- **Then** un dialog de confirmation s'affiche "Déjà envoyé le JJ/MM/YYYY à <email>, envoyer à nouveau ?" avec les options "Annuler" et "Renvoyer"
- **And** si le bailleur confirme, l'email est renvoyé et `sent_at` / `sent_to_email` sont mis à jour

**AC3 — Tenant sans email**
- **Given** une quittance liée à un bail dont le tenant n'a pas d'email (`tenants.email IS NULL`)
- **When** le bailleur clique sur "Envoyer par email"
- **Then** l'Edge Function retourne HTTP 422, le bouton reste disponible, un toast d'erreur s'affiche : "Impossible d'envoyer : votre locataire n'a pas d'adresse email. Mettez à jour sa fiche pour activer l'envoi."

**AC4 — Quittance void**
- **Given** une quittance annulée (`voided_at IS NOT NULL`)
- **When** le bailleur consulte la liste
- **Then** le bouton "Envoyer par email" est disabled (état visuel grisé) sans message d'erreur

**AC5 — Quittance stale**
- **Given** une quittance marquée `is_stale = true` (paiement inclus supprimé après émission)
- **When** le bailleur consulte la liste
- **Then** le bouton "Envoyer par email" est disabled avec tooltip ou badge "Données modifiées — invalide"

**AC6 — Isolation cross-user (RLS)**
- **Given** un propriétaire B authentifié tente d'invoquer `send-receipt` avec le `receipt_id` appartenant au propriétaire A
- **When** l'Edge Function est appelée
- **Then** la fonction retourne HTTP 403 "Forbidden", aucun email n'est envoyé, `sent_at` n'est pas modifié

**AC7 — Rate-limit Resend**
- **Given** le quota mensuel Resend est épuisé (réponse 429 de l'API Resend)
- **When** le bailleur tente un envoi
- **Then** l'Edge Function retourne HTTP 429, un toast d'erreur affiche "Quota d'envoi dépassé pour ce mois. Réessayez à partir du 1er du mois prochain."

**AC8 — Audit trail**
- **Given** un envoi réussi
- **When** le bailleur consulte la liste des quittances
- **Then** chaque quittance envoyée affiche une mention "Envoyé le JJ/MM/YYYY à <email partiel masqué>*" (* ex: "j***@example.com" — masquage partiel RGPD)

**AC9 — Sécurité secrets**
- **Given** le code Flutter (client) ou le bundle JavaScript servi par Firebase Hosting
- **When** il est inspecté (DevTools, bundle analysis)
- **Then** la clé `RESEND_API_KEY` est introuvable — elle n'existe que dans les secrets de l'Edge Function Supabase

**AC10 — PDF absent (edge case)**
- **Given** une quittance dont `pdf_path IS NULL` (cas anormal — Storage failure lors de la génération)
- **When** le bailleur tente un envoi
- **Then** l'Edge Function retourne HTTP 422 "PDF non disponible pour cette quittance. Régénérez-la.", aucun email n'est envoyé

---

## Dépendances

**Tables Supabase** :
- `public.receipts` / `dev.receipts` : colonnes `sent_at TIMESTAMPTZ` et `sent_to_email TEXT` à ajouter par migration
- `public.leases` : lecture `tenant_id`
- `public.tenants` : lecture `email`
- `public.landlords` : lecture `full_name` (pour le corps de l'email)
- Bucket Storage `receipts/` : URL signée 5 min pour téléchargement PDF côté Edge Function

**Features bloquantes** :
- FEAT-007 : table `receipts` avec `pdf_path`, bucket Storage, UI `LeaseReceiptsPage` / `ReceiptListTile`

**Infrastructure** :
- `RESEND_API_KEY` provisionné dans Supabase Edge Function Secrets (staging + prod)
- Domaine email vérifié dans Resend (ex : `noreply@easyrent.app`) — prérequis infra avant déploiement

**Dépendances Deno** :
- `@supabase/supabase-js@2.45.0` (déjà utilisé dans `generate-receipt`)
- Client HTTP natif Deno (`fetch`) — pas de SDK Resend nécessaire (API REST simple)

---

## Legal / compliance notes

- **Loi du 6 juillet 1989, art. 21** : la quittance doit être remise gratuitement au locataire qui la demande. L'email constitue une remise valable à condition que le locataire ait accepté ce canal. Pour le MVP, on suppose l'acceptation implicite (email dans la fiche locataire = consentement). À documenter dans `/privacy`.
- **RGPD — données transmises à Resend** : l'email du locataire et son prénom/nom transitent vers le serveur Resend (hébergé hors UE potentiellement). Vérifier le DPA Resend et l'adéquation (Standard Contractual Clauses). À documenter dans `/privacy`. Pour le MVP : Resend est conforme GDPR (DPA disponible).
- **RGPD — `sent_to_email` en base** : donnée personnelle (email locataire). Couverte par la base légale "obligation contractuelle / légale" (art. 6.1.b et 6.1.c RGPD). Conservation : 5 ans minimum (même régime que `receipts`). Pas de hard-delete.
- **Masquage `sent_to_email` en UI** : l'email du locataire ne doit pas être affiché en clair dans l'interface si un tiers peut voir l'écran. Masquage partiel recommandé (AC8).
- **Immuabilité** : `sent_at` et `sent_to_email` sont mis à jour par l'Edge Function via RPC ou UPDATE direct avec ownership check — pas de policy UPDATE directe sur `receipts` (conforme décision FEAT-007 : pas de policy UPDATE côté client).

---

## Risques & contraintes

| Risque | Mitigation |
|---|---|
| Domaine email non vérifié dans Resend au moment du dev | Utiliser le sandbox Resend (emails interceptés, non délivrés) pendant les tests |
| `pdf_path` absent si FEAT-007 Phase 2 a échoué silencieusement | AC10 : retourner 422 explicite, ne pas masquer le problème |
| Fuite de `RESEND_API_KEY` côté client | AC9 + garde-fou CLAUDE.md : jamais de `re_*` côté client |
| Renvoi accidentel multiple | D2 : dialog de confirmation si `sent_at IS NOT NULL` |
| Resend rate-limit 3 000/mois | D5 : erreur 429 explicite, acceptable pour MVP |
| Edge Function timeout si PDF volumineux | URL signée + `fetch` côté Deno suffisent (PDF < 1 Mo) ; timeout 540s largement suffisant |

---

## Estimation

**Priorité** : P0 (MVP)

**Effort** : M (1-3 jours)

Décomposition approximative :
- Migration SQL (`sent_at`, `sent_to_email`) : 0,25 jour
- Edge Function `send-receipt` (Deno) : 0,75 jour
- Flutter UI (bouton, états, dialog renvoi, toast) : 0,75 jour
- Tests (RLS cross-user, widget, E2E sandbox Resend) : 0,5 jour
- Infra (secret Resend staging, domaine vérifié) : 0,25 jour

---

## Definition of Done

- [ ] Migration `sent_at` + `sent_to_email` appliquée (public + dev), RLS inchangée
- [ ] Edge Function `send-receipt` déployée, `RESEND_API_KEY` secret posé en staging
- [ ] Ownership check cross-user retourne 403 (testé manuellement ou en RLS test)
- [ ] Envoi sandbox Resend validé bout-en-bout (email reçu, PDF joint correct)
- [ ] `sent_at` renseigné après envoi réussi, affiché dans l'UI
- [ ] Bouton disabled si quittance void ou stale
- [ ] Toast d'erreur sur 422 et 429
- [ ] Dialog de confirmation si renvoi (D2)
- [ ] `RESEND_API_KEY` absent du bundle Flutter (audit bundle)
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Déployé Firebase Hosting staging

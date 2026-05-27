# [FEAT-001] Authentification magic link

## User story
En tant que **propriétaire bailleur**, je veux **me connecter à EasyRent via un lien envoyé par email** afin de **accéder à mon espace de gestion locative de façon sécurisée, sans avoir à retenir un mot de passe**.

## Context & motivation
Le propriétaire est souvent un particulier peu technophile. Le magic link supprime la friction du mot de passe tout en maintenant un niveau de sécurité acceptable (possession de l'email = facteur d'authentification). Supabase Auth fournit cette fonctionnalité nativement — l'intégration doit se faire côté Flutter (gestion du deep link / redirect URL) et Riverpod (état d'auth global).

## Acceptance criteria (Gherkin)

**Signup — premier accès**
- **Given** un visiteur non authentifié sur `/login`
  **When** il saisit son adresse email et clique sur "Recevoir mon lien de connexion"
  **Then** Supabase envoie un email contenant un lien de connexion à usage unique, et l'UI affiche le message "Vérifiez votre boîte mail — un lien de connexion vous a été envoyé."

- **Given** le visiteur clique sur le lien magic link dans son email
  **When** Supabase valide le token
  **Then** l'utilisateur est redirigé vers `/` (dashboard), un enregistrement est créé dans `landlords` s'il s'agit de son premier accès, et la session Supabase est stockée en mémoire.

**Login — accès ultérieur**
- **Given** un propriétaire déjà inscrit sur `/login`
  **When** il saisit son email et clique sur "Recevoir mon lien de connexion"
  **Then** Supabase envoie un nouveau lien et l'UI affiche le même message de confirmation.

**Garde de route**
- **Given** un utilisateur non authentifié
  **When** il tente d'accéder à n'importe quelle route protégée (ex: `/properties`)
  **Then** il est redirigé vers `/login`.

- **Given** un utilisateur authentifié
  **When** il navigue vers `/login`
  **Then** il est redirigé vers `/`.

**Déconnexion**
- **Given** un utilisateur authentifié
  **When** il clique sur "Déconnexion" dans le menu
  **Then** la session Supabase est révoquée, le state Riverpod est réinitialisé, et il est redirigé vers `/login`.

**RGPD — consentement signup**
- **Given** un nouvel utilisateur sur `/login`
  **When** il voit le formulaire
  **Then** une case à cocher non pré-cochée est présente avec le texte "J'accepte la politique de confidentialité" (lien cliquable vers l'URL de la politique). L'envoi du formulaire est désactivé tant que la case n'est pas cochée.

**Validation formulaire**
- **Given** le champ email est vide ou contient une adresse invalide
  **When** l'utilisateur tente de soumettre
  **Then** un message d'erreur inline s'affiche ("Adresse email invalide"), aucun appel Supabase n'est effectué.

## Out of scope
- Connexion par mot de passe (jamais — décision produit actée)
- Reset password (jamais — même raison)
- OAuth (Google, Apple) — P1 au plus tôt
- Gestion multi-comptes / rôles — P1
- 2FA — P2
- Emails transactionnels personnalisés (template Supabase) — P1

## Dependencies
- Tables Supabase : `landlords` (créée dans FEAT-002 — mais le trigger de création `landlords` peut être intégré ici en tant que migration conjointe ou dans FEAT-002)
- Features bloquantes : aucune (FEAT-001 est le point de départ de la chaîne)
- Infrastructure : redirect URL Supabase configurée pour le domaine Firebase Hosting (dev + prod)

## Legal / compliance notes
- **RGPD** : consentement explicite obligatoire au signup (case à cocher non pré-cochée, lien vers politique de confidentialité). Voir `docs/LEGAL.md`.
- **Données personnelles** : l'adresse email est une donnée personnelle — son traitement doit être mentionné dans la politique de confidentialité.
- Pas de conservation de session au-delà de la session navigateur (pas de "se souvenir de moi" en V1 — conforme au principe de minimisation).

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] RLS testée (cross-user — vérifier qu'un utilisateur ne peut pas accéder aux données d'un autre)
- [ ] Tests widget : formulaire login, validation email, case RGPD
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Migration Supabase appliquée sur `dev` et `public` (trigger création `landlords`)
- [ ] Déployé sur Firebase Hosting (env dev)
- [ ] Redirect URL magic link configurée et testée (dev + prod)

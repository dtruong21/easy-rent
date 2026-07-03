# [FEAT-025] Écran Profil → vrai paramétrage

## User story

En tant que **bailleur utilisateur de Baillan**, je veux **un écran de paramétrage complet (sécurité du compte, contact support)** afin de **gérer mon compte comme sur n'importe quel SaaS, sans devoir écrire à un email inconnu ou rester bloqué avec un mot de passe que je ne peux pas changer**.

## Context & motivation

`/profile` a été livré récemment (commits 50d1a71+) avec un formulaire d'identité (mentions quittances loi 1989), un sélecteur de thème, des liens légaux, une section « À propos » et un bouton de déconnexion. C'est un profil, pas un paramétrage : aucune action de compte n'y est possible (changer son mot de passe, contacter le support, exporter ses données). L'item roadmap P1-001 « Profile utilisateur avancé (password change, avatar, 2FA) » formalise cette dette depuis le début du MVP.

Douleur concrète : un bailleur qui veut changer son mot de passe aujourd'hui n'a aucun moyen de le faire depuis l'app — il doit soit se souvenir du flow « mot de passe oublié » sur `/login` (peu découvrable une fois connecté), soit ne pas pouvoir le faire du tout.

## Décision de scoping (V1 vs V2+)

Le tri ci-dessous priorise **ce qui est réalisable sans toucher `firestore.rules` / `functions/`** (contrainte dure : ces fichiers ont des modifications locales non commitées sur la branche courante, et le deploy des Cloud Functions y est cassé — voir Risques) et **sans complexité de réauthentification interactive**.

| # | Option | Décision | Raison |
|---|---|---|---|
| 1 | Changement de mot de passe | **V1** | Réalisable via `sendPasswordResetEmail` (déjà utilisé par le flow « mot de passe oublié », `auth_repository.dart:194`) — zéro nouvelle CF, zéro réauth interactive |
| 2 | Nous contacter / support | **V1 (mailto)** | `mailto:` avec sujet/corps pré-remplis (UID, version app) — zéro nouvelle collection, zéro CF |
| 5 | Changement d'email | **Hors scope V1** | Identifiant d'auth, nécessite vérification + révoque tous les tokens — pas demandé explicitement par l'utilisateur |
| 3 | Export des données (RGPD art. 20) | **V2** | Faisable sans nouvelle CF (lecture directe des collections `landlords/properties/tenants/leases` scoped au user) mais dépasse le budget de ce sprint — item roadmap distinct |
| 4 | Suppression de compte (RGPD art. 17) | **V2 — point de contact en V1** | Rétention légale quittances 5 ans (`legalHold`) → suppression ≠ purge totale, nécessite une Cloud Function dédiée (anonymisation + cascade). Le canal support V1 sert de garde-fou temporaire |
| 6 | 2FA/TOTP | **V2** | Item P1 roadmap distinct, hors urgence — pas mentionné par l'utilisateur |
| 7 | Notifications / langue | **Hors scope** | App FR-only, pas de système de notifications (email transactionnel uniquement à ce stade) |

## Scope V1

### V1.1 — Changement de mot de passe (formulaire in-app — décision utilisateur 2026-07-03)

**Approche retenue (RÉVISÉE)** : l'utilisateur a tranché contre la proposition initiale (lien email) — formulaire in-app **mot de passe actuel + nouveau + confirmation**. Flow Firebase : `reauthenticateWithCredential(EmailAuthProvider.credential(email, actuel))` puis `updatePassword(nouveau)`. Validation du nouveau mot de passe = mêmes règles que le signup (`PasswordValidator` : 8 caractères min, 1 lettre, 1 chiffre). Erreurs couvertes : mot de passe actuel erroné, nouveau trop faible, confirmation différente, too-many-requests. Succès → snackbar + champs vidés, session conservée.

**Détection compte social (Google/Apple)** : ces comptes n'ont pas de mot de passe Firebase Auth (`user.providerData` ne contient pas `password` comme `providerId`). **Décision utilisateur (2026-07-03, tranchée en cours de sprint)** : le changement de mot de passe est réservé **uniquement** aux comptes créés avec email — pour Google/Apple, l'option n'apparaît **pas du tout** (ni bouton désactivé, ni état informatif). Critère technique : présence du provider `password` dans `providerData` (couvre aussi le cas d'un compte social lié ultérieurement à un mot de passe).

**Acceptance criteria (Gherkin)** :

```gherkin
Scénario : bailleur avec mot de passe demande un changement
  Given je suis connecté avec un compte email + mot de passe
  And je suis sur /profile, section "Sécurité"
  When je clique sur "Changer mon mot de passe"
  Then un email de réinitialisation est envoyé à mon adresse
  And un message confirme "Un email vous a été envoyé pour définir un nouveau mot de passe"
  And je ne suis pas déconnecté de ma session actuelle

Scénario : bailleur connecté via Google (sans provider password)
  Given je suis connecté via Google (providerData contient "google.com", pas "password")
  And je suis sur /profile
  Then aucune option de changement de mot de passe n'apparaît
  # décision utilisateur 2026-07-03 : réservé aux comptes email — rien d'affiché pour les sociaux

Scénario : bailleur connecté via Apple (sans provider password)
  Given je suis connecté via Apple (providerData contient "apple.com", pas "password")
  Then aucune option de changement de mot de passe n'apparaît

Scénario : session anonyme (essai sans compte)
  Given je suis en session anonyme (isAnonymous == true)
  Then la section "Sécurité" n'affiche aucune option de mot de passe
  # cohérent avec le fait qu'un compte anonyme n'a ni email ni mot de passe

Scénario : échec d'envoi (rate limit / erreur réseau)
  Given je clique sur "Changer mon mot de passe"
  When l'appel sendPasswordResetEmail échoue
  Then un message d'erreur générique s'affiche ("Réessayez dans quelques instants")
  And aucune exception non gérée ne remonte à l'UI
```

**Hors scope V1.1** : formulaire ancien/nouveau mot de passe in-app avec `reauthenticateWithCredential` — reporté en V2 si le besoin UX (éviter de sortir vers un email) devient prioritaire.

### V1.2 — Nous contacter / support (formulaire in-app — décision utilisateur 2026-07-03)

**Approche retenue (RÉVISÉE)** : l'utilisateur a tranché contre le `mailto:` — formulaire in-app (sujet + message) enregistré dans une **nouvelle collection Firestore `support_requests`** (landlordId, email, subject, message, appVersion, appEnv, createdAt, status:'new'), create-only côté client (pas de lecture/édition en V1). Nécessite un bloc de rules dédié — l'orchestrateur isole le commit du hunk WIP local (stash) et déploie les rules avec le fix local `landlords/get resource==null` préservé (déjà actif en pratique). **Notification** : email vers daki.tle.26@gmail.com à chaque demande — canal à trancher en fin de sprint (extension Firebase Trigger Email / Cloud Function après réparation du deploy functions / consultation console en attendant) ; le formulaire se livre indépendamment de la notification.

**Acceptance criteria (Gherkin)** :

```gherkin
Scénario : bailleur clique sur "Nous contacter"
  Given je suis sur /profile, section "Support"
  When je clique sur "Nous contacter"
  Then mon client email s'ouvre (ou un nouvel onglet mailto selon plateforme)
  And le destinataire est pré-rempli avec l'adresse support Baillan [DÉCISION À TRANCHER]
  And le sujet est pré-rempli (ex. "Support Baillan — <UID tronqué>")
  And le corps contient un pied de contexte technique (version app, environnement)
    mais aucune donnée personnelle sensible du bailleur non déjà connue de lui

Scénario : plateforme sans client mail configuré
  Given aucun client email n'est configuré sur l'appareil/navigateur
  When je clique sur "Nous contacter"
  Then le comportement dégrade proprement (l'OS/navigateur affiche son propre message —
    pas de crash silencieux côté Baillan)
```

**Hors scope V1.2** : formulaire in-app, ticketing, chat support — reportés en V2 si le volume de support le justifie.

## Scope V2+ (reporté)

| Item | Raison du report |
|---|---|
| Export des données (RGPD art. 20) | Fonctionnellement indépendant du reste de ce sprint ; mérite sa propre story avec ses propres critères d'acceptation (format export : JSON ? PDF récapitulatif ? périmètre exact des collections) |
| Suppression de compte (RGPD art. 17) | Nécessite une Cloud Function dédiée (anonymisation vs hard-delete, cascade vers properties/tenants/leases, préservation `legalHold` sur receipts 5 ans) — le deploy `functions/` est actuellement cassé sur cette branche, prérequis bloquant. Le canal support V1.2 sert de garde-fou temporaire pour toute demande de suppression |
| Changement d'email | Identifiant d'auth Firebase, nécessite re-vérification email + gestion des tokens de session existants — pas demandé par l'utilisateur, complexité disproportionnée pour ce sprint |
| 2FA/TOTP | Item P1 roadmap distinct (`docs/state/INDEX.md` — "Password change + 2FA"), non mentionné dans la demande utilisateur, scope technique conséquent (enrollment TOTP, codes de secours) |
| Formulaire de contact in-app | Nécessite nouvelle collection + rules + éventuellement CF de notification — à réévaluer si le `mailto:` V1.2 s'avère insuffisant en usage réel |
| Avatar / photo de profil | Mentionné dans l'item roadmap P1-001 générique mais pas dans la demande utilisateur explicite ; nécessite Storage bucket dédié + upload UI |

## Décisions utilisateur (tranchées 2026-07-03)

1. ~~Adresse email de support (mailto)~~ → **pivot : formulaire in-app + base de données** ; notification à envoyer vers **daki.tle.26@gmail.com**.
2. ~~Lien email pour le mot de passe~~ → **pivot : formulaire in-app** (actuel + nouveau + confirmation, réauthentification Firebase).
3. **Réservé aux comptes email** : l'option mot de passe n'apparaît QUE si `providerData` contient `password` — rien d'affiché pour Google/Apple/anonyme.

## Décision restante (fin de sprint)

- **Canal de notification email des demandes support** : (a) extension Firebase « Trigger Email » (config console + SMTP, zéro code repo), (b) Cloud Function onCreate après merge du fix deploy functions (branche ADR 0001), (c) V1 sans notif — consultation console Firestore. Le formulaire est livré quoi qu'il en soit.

## Out of scope

- Formulaire ancien/nouveau mot de passe in-app avec réauthentification (V2 si besoin confirmé)
- Formulaire de contact in-app / ticketing (V2)
- Export de données RGPD (story séparée, V2)
- Suppression de compte (story séparée, V2 — nécessite CF dédiée)
- Changement d'email (non demandé, complexité disproportionnée)
- 2FA/TOTP (item roadmap distinct)
- Avatar / photo de profil
- Notifications, préférences de langue (app FR-only)

## Dependencies

- **Firestore** : aucune nouvelle collection ni règle requise (V1 entier est client-only + Firebase Auth SDK natif)
- **Fichiers intouchables sur cette branche** : `firestore.rules`, `functions/package.json` ont des modifications locales non commitées — **aucune tâche de ce sprint ne doit les modifier**. C'est la raison structurante du choix `mailto:` plutôt que formulaire, et `sendPasswordResetEmail` plutôt que nouvelle CF de changement de mot de passe.
- **Features bloquantes** : aucune — s'appuie uniquement sur `AuthRepository` existant (FEAT-011) et `ProfilePage` existante (commits 50d1a71+)
- **Package Flutter potentiellement requis** : `url_launcher` pour le `mailto:` (à vérifier si déjà présent dans `pubspec.yaml` — sinon ajout mineur)

## Legal / compliance notes

- **RGPD** : le canal support V1.2 doit pouvoir absorber les demandes d'exercice de droits (accès, effacement, portabilité) tant que les stories V2 dédiées ne sont pas livrées — c'est un filet de sécurité, pas une solution définitive. Ne pas communiquer ce canal comme "solution RGPD" dans l'UI (juste "Nous contacter" / "Support"), pour éviter une fausse impression de conformité complète.
- **Nouvelle collecte de données personnelles (révisé après pivot formulaire, audit 2026-07-03)** : `support_requests` stocke email + message côté Baillan (sous-traitant Google/Firestore). Base légale : intérêt légitime (art. 6.1.f). Documentée dans la politique de confidentialité v1.1 (sections 2, 3 et 5 — rétention : traitement de la demande + 12 mois max). Suivi non bloquant : rate-limit à adjoindre au canal de notification (V2) + durcissement `hasOnly` des rules (itération ultérieure).
- **Mot de passe** : le flow email reset (V1.1) ne nécessite aucune donnée supplémentaire — il réutilise l'infrastructure Firebase Auth déjà auditée pour FEAT-011.

## Risks / contraintes techniques

1. **`reauthenticateWithCredential` évité intentionnellement** : Firebase Auth exige une session récente pour `updatePassword()` direct. Le contournement par email (`sendPasswordResetEmail`) évite ce piège UX (formulaire de reauth = friction + code additionnel), au prix d'un aller-retour email au lieu d'un changement instantané in-app. Assumé comme bon compromis V1.
2. **Comptes sociaux sans mot de passe** : `user.providerData` doit être inspecté (`providerId == 'password'` vs `'google.com'` vs `'apple.com'`) pour décider de l'affichage. Ne jamais proposer un bouton actif à un compte qui n'a pas de credential mot de passe — l'appel échouerait silencieusement ou avec une erreur Firebase peu claire pour l'utilisateur.
3. **`firestore.rules` et `functions/package.json` intouchables** : toute idée qui nécessiterait une nouvelle règle ou une nouvelle Cloud Function est de facto reportée en V2, indépendamment de sa valeur produit — contrainte d'exécution de ce sprint, pas un jugement sur la priorité produit à long terme.
4. **RGPD art. 17 (droit à l'effacement) non traité en V1** : le canal support V1.2 gère la demande manuellement en attendant la CF dédiée V2. Assumer un processus manuel côté équipe (pas d'automatisation) tant que V2 n'est pas livrée.
5. **`mailto:` comportement plateforme-dépendant** : sur certains navigateurs/OS sans client mail configuré, le comportement de fallback est hors du contrôle de Baillan — à documenter comme limitation connue plutôt qu'à tenter de la corriger.

## Priority

P1 (post-MVP) — formalise l'item roadmap existant "Password change + 2FA" (voir `docs/state/INDEX.md` ligne 120) et "Profile utilisateur avancé" (`docs/BACKLOG.md` P1-001).

## Estimated effort

**S/M** — décomposable en 2 sous-tâches indépendantes et parallélisables :
- V1.1 (changement mot de passe + détection provider) : S (< 1 jour)
- V1.2 (mailto contact) : S (< 1 jour, quasi-trivial si `url_launcher` déjà dans `pubspec.yaml`)

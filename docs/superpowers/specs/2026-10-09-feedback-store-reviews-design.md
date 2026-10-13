# FEAT-060 — Avis in-app et notation sur les stores — design

> Statut : validé par Daki le 2026-10-09 (brainstorming). Une seule PR vers
> `develop`.

## Objectif

Deux besoins, deux canaux séparés :

1. **Retours produit** (web et mobile) : recueillir une note et un commentaire
   des bailleurs pour orienter Baillan.
2. **Notes sur les stores** (apps iOS/Android) : obtenir des étoiles sur
   l'App Store et Google Play pour la visibilité des apps.

Aujourd'hui l'app n'a que « Nous contacter » (FEAT-025, `support_requests`) ;
la vitrine a un formulaire d'idées Tally. Ni demande de note, ni avis.

## Décisions produit (2026-10-09)

| Sujet | Décision |
|---|---|
| Objectif | Les deux : notes stores + retours produit |
| Canal des retours | Formulaire in-app (note 1-5 + commentaire), stocké chez nous |
| Stockage | **Réutiliser `support_requests`** (`kind: 'feedback'`), pas de nouvelle collection |
| Notation stores | Fenêtre native automatique **et** bouton « Noter l'app » dans le profil |
| Moment de la demande automatique | **15 jours d'usage** : compte complet créé depuis ≥ 15 jours **et** au moins un bien |
| Web | Carte discrète « Votre avis compte » sur l'Accueil (même condition) |
| Fréquence | Au plus une sollicitation automatique tous les **120 jours** par appareil |

## Conformité stores (non négociable)

- **Apple 5.6.1** : la demande de note passe par l'API native
  (`SKStoreReviewController`, via `in_app_review`) ; Apple décide de
  l'afficher (3 fois par an maximum).
- **Google Play (In-App Review)** : interdit de poser une question (« Vous
  aimez l'app ? ») avant ou pendant la demande.
- **Aucun tri des avis** : la fenêtre native n'est jamais précédée d'une
  question ; une note du formulaire in-app, haute ou basse, ne renvoie jamais
  vers le store. Les deux canaux restent indépendants.

## 1. Formulaire « Donner mon avis » (web et mobile)

### Écran

- Entrée **« Donner mon avis »** dans le profil, section Aide, à côté de
  « Nous contacter ». Ouvre la route **`/profile/feedback`**, réservée aux
  comptes complets (même garde que `/profile/support`).
- Note **1 à 5 étoiles, obligatoire** ; commentaire **facultatif**, ≤ 2000
  caractères ; bouton « Envoyer ».
- Succès : message de remerciement (snackbar) et retour à l'écran précédent.
  Échec : message d'erreur, formulaire conservé, nouvel essai possible.

### Données — `support_requests/{id}`, nouvelle forme « avis »

Champs existants conservés : `landlordId`, `email`, `subject`, `message`,
`appVersion`, `appEnv`, `status` (`'new'`), `createdAt` (`request.time`).
Nouveaux champs :

| Champ | Type | Règle |
|---|---|---|
| `kind` | string | `'feedback'` pour un avis. **Absent = demande de support** (documents existants inchangés) |
| `rating` | int | 1 à 5, uniquement pour un avis |
| `platform` | string | `'web'`, `'ios'` ou `'android'` (avis uniquement) |

- `subject` est rempli par l'app : « Avis — {note}/5 ».
- `message` = commentaire, **vide autorisé** pour un avis.

### Règles Firestore

- La création d'une **demande de support** reste **strictement identique**
  (mêmes contrôles, `kind` absent).
- Nouvelle branche pour un **avis** : `isFullyAuthed()`, `landlordId ==
  request.auth.uid`, `kind == 'feedback'`, `rating` entier de 1 à 5,
  `platform` dans la liste, `subject` 1-120 caractères, `message` 0-2000
  caractères, `email` non vide, `appVersion` / `appEnv` chaînes,
  `status == 'new'`, `createdAt == request.time`.
- Lecture, modification, suppression : toujours refusées côté client.
- Lecture par Daki dans la console Firebase (filtre `kind == 'feedback'`).
  Export RGPD et suppression de compte : déjà couverts pour
  `support_requests`.

## 2. Notation stores (mobile) et carte web

### Éligibilité (fonction pure, partagée)

`true` si et seulement si :
- session **complète** (jamais un compte anonyme ni non connecté) ;
- `LandlordProfile.createdAt` ≤ maintenant − 15 jours ;
- au moins **un bien** (non archivé) ;
- dernière sollicitation automatique sur cet appareil > 120 jours (ou jamais).

La date de la dernière sollicitation est gardée **sur l'appareil**
(`SharedPreferences`, localStorage sur le web), comme le mode d'affichage des
cartes.

### Apps iOS/Android (`isStoreApp`)

- **Demande automatique** : à l'ouverture de l'**Accueil**, si éligible et
  `InAppReview.isAvailable()`, appel de `requestReview()`, puis
  enregistrement de la date (que la fenêtre s'affiche ou non — c'est le
  store qui décide). Aucune question préalable.
- **Bouton « Noter l'app »** dans le profil : `openStoreListing(...)`.
  - Android : nom du paquet, toujours disponible.
  - iOS : identifiant App Store numérique, dart-define **`APP_STORE_ID`**
    (connu dès la création de la fiche dans App Store Connect). **Bouton
    masqué sur iOS tant qu'il est absent.**
- La carte web n'apparaît jamais dans les apps.

### Web

- **Carte « Votre avis compte »** sur l'Accueil quand éligible : « Donner mon
  avis » (ouvre `/profile/feedback`) ou croix de fermeture. Après l'une ou
  l'autre action, la date est enregistrée → carte masquée 120 jours.
- Ni fenêtre native, ni bouton « Noter l'app » sur le web (pas de store).

### Dépendance

`in_app_review` (pub.dev), appelée uniquement dans les apps (`isStoreApp`).
Isolée derrière une petite interface pour les tests (faux sans appel au
store). Vérifier que le build web compile et ne charge rien de ce paquet
(cf. `packages/purchases_flutter_web_noop`, FEAT-044e) — s'il embarque un
plugin web actif, le neutraliser de la même façon.

## 3. Tests, documentation, mise en ligne

### Tests

- **Règles** (`functions/rules-tests/firestore_rules.test.ts`) : avis valide
  accepté ; refus pour `rating` 0, 6 ou non entier, `kind` inconnu,
  `platform` inconnue, autre `landlordId`, compte anonyme ; création de
  support inchangée (cas existants verts) ; lecture refusée.
- **Éligibilité** (unitaire) : < 15 jours, aucun bien, sollicitation il y a
  < 120 jours, anonyme → faux ; cas nominal → vrai ; bornes (15 j, 120 j).
- **Écrans** : formulaire (note obligatoire, envoi, erreur) ; entrées du
  profil (« Donner mon avis » partout, « Noter l'app » seulement en app store
  et, sur iOS, seulement avec `APP_STORE_ID`) ; carte web (affichée,
  « Donner mon avis », fermée, masquée 120 jours, jamais en app store).
- **Demande automatique** : avec un faux `in_app_review` — appelée une fois
  si éligible, jamais sinon, date enregistrée.

### Documentation

- `docs/state` : schéma `support_requests` (`kind`, `rating`, `platform`),
  route `/profile/feedback`, `FEATURES.md` (FEAT-060), `CHANGELOG.md`.
- `docs/STORE_COMPLIANCE.md` : demande de note native, sans question
  préalable, aucun tri des avis.
- `docs/MOBILE.md` : dart-define `APP_STORE_ID` pour les builds de release
  iOS.
- Textes FR et EN (l10n).

### Mise en ligne

- Règles Firestore : par la CI (`develop` → base `staging` ; `main` →
  `(default)`). Aucune Cloud Function modifiée.
- Apps : la demande automatique n'a d'effet qu'une fois les apps publiées ;
  ajouter `APP_STORE_ID` aux builds de release iOS.

## Hors périmètre

Notification e-mail des nouveaux avis (même chantier que FEAT-025 V2),
écran de lecture des avis dans l'app, NPS, avis publics sur le web
(Trustpilot, Google), demande de note sur le web.

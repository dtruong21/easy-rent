# Runbook formulaires consoles — Play Console & App Store Connect

> Compagnon opérationnel de [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md)
> (§6, étape 4). Réponses **prêtes à copier** pour chaque formulaire, établies
> le 2026-07-07 pour l'état V1 de Baillan : **gratuite, sans pub, sans IAP,
> sans analytics/crashlytics** (vérifié dans pubspec), uploads de documents
> PDF + images. ⚠️ À re-dérouler si l'app change (FEAT-044 IAP notamment —
> les items concernés sont marqués 🔁 FEAT-044).

## 0. Prérequis communs

| Élément | Valeur |
|---|---|
| Privacy policy URL | `https://easy-rent-54cd4.web.app/privacy` |
| URL de demande de suppression (FEAT-045, session en cours) | `https://easy-rent-54cd4.web.app/delete-account` |
| Compte démo review (à créer, cf. §3) | `review.stores@<domaine choisi>` + mot de passe dédié |
| Catégorie d'app | Play : *House & Home* (ou *Finance* — recommandé : House & Home) ; Apple : *Utilities* ou *Finance* (primaire), *Productivity* (secondaire) |

---

## 1. Google Play Console → Politique → Contenu de l'app

Dérouler **tous** les formulaires listés ; chacun est bloquant s'il est incomplet.

### 1.1 Règles de confidentialité
- URL : `https://easy-rent-54cd4.web.app/privacy`

### 1.2 Annonces (Ads)
- « Mon appli ne contient pas d'annonces » → **Non, pas d'annonces**

### 1.3 Accès à l'appli (App access)
- « Tout ou partie des fonctionnalités est limitée » → **fournir des identifiants**
- Ajouter une instruction « All functionality available with these credentials »
- Identifiants : ceux du compte démo (§3). Texte d'instructions (**en anglais**, exigé) :

```
Baillan is a rental-management app for French landlords (UI in French).
Log in with the provided email/password credentials (tap « J'ai déjà un
compte » on the landing page). The demo account is pre-populated with one
property, one tenant, an active lease, recorded rent payments and a
generated rent receipt (PDF), so all features are reachable:
Accueil (dashboard) / Biens (properties) / Locataires (tenants) /
Baux (leases) → payments & receipts / Profil (settings, account deletion).
No OTP/2FA. Google & Apple sign-in are alternative login methods to the
same feature set — the email/password account exposes 100% of features.
The anonymous mode (« Continuer sans compte ») is a 14-day demo tier.
```

### 1.4 Classification du contenu (questionnaire IARC)
- Email de contact : email développeur
- Catégorie : **Utilitaire, productivité, communication ou autre**
- Violence / sexualité / langage grossier / substances / jeux d'argent
  (réels ou simulés) : **Non** partout
- Interactions entre utilisateurs (chat, contenus visibles par d'autres) :
  **Non** (support privé 1:1 uniquement)
- Partage de la position : **Non**
- Achats numériques : **Non** 🔁 FEAT-044 → repasser à Oui et refaire le
  questionnaire
- Résultat attendu : **PEGI 3 / Everyone**

### 1.5 Audience cible et contenu
- Tranche d'âge cible : **18 ans et plus** uniquement (outil professionnel
  bailleurs — évite toute entrée dans la politique Families)
- « L'appli pourrait-elle attirer involontairement les enfants ? » : **Non**

### 1.6 Applis d'actualités / COVID / Applis gouvernementales / Santé
- **Non** aux quatre (santé : « aucune fonctionnalité de santé »)

### 1.7 Fonctionnalités financières
- **« Mon appli ne propose aucune fonctionnalité financière »**
- Justification si demandée : l'app **enregistre** des loyers déjà perçus
  (suivi/registre) ; elle n'octroie pas de crédit, ne traite ni ne route
  aucun paiement, ne donne pas de conseil financier. 🔁 FEAT-044 (abonnement
  Pro via IAP) ne change PAS cette réponse.

### 1.8 Sécurité des données (Data safety) — question par question

**Questions globales :**
- « Votre appli collecte-t-elle ou partage-t-elle des types de données
  utilisateur requis ? » → **Oui**
- « Toutes les données utilisateur collectées sont-elles chiffrées en
  transit ? » → **Oui** (TLS Firebase)
- « Proposez-vous un moyen de demander la suppression des données ? » →
  **Oui** → URL : `https://easy-rent-54cd4.web.app/delete-account`
- Section « Suppression de compte » : chemin in-app **Oui** (FEAT-045) +
  même URL web

**Types de données — pour CHAQUE ligne ci-dessous, répondre :**
Collectée = Oui · Partagée = **Non** · Traitée de façon éphémère = Non ·
Finalités = **Fonctionnement de l'appli** + **Gestion du compte** (pour les
données du profil)

| Catégorie Play | Type | Obligatoire ou facultatif ? |
|---|---|---|
| Infos personnelles | Nom | Obligatoire (compte) — les noms de locataires sont saisis à l'initiative de l'utilisateur → Facultatif |
| Infos personnelles | Adresse e-mail | Obligatoire (compte) |
| Infos personnelles | N° de téléphone | Facultatif (profil + locataires) |
| Infos personnelles | Adresse | Facultatif (profil, biens, locataires) |
| Infos financières | Autres infos financières | Facultatif (loyers, paiements, dépôts — saisis par l'utilisateur) |
| Photos et vidéos | Photos | Facultatif (justificatifs/documents jpg-png-webp uploadés) |
| Fichiers et documents | Fichiers et documents | Facultatif (PDF baux, quittances, justificatifs) |
| Activité dans l'appli | Autre contenu généré par l'utilisateur | Facultatif (demandes de support) |
| ID de l'appareil ou autres ID | ID d'appareil ou autres ID | Obligatoire (Firebase installation ID, UID Auth) |

**Ne PAS déclarer** (vérifié absent du pubspec) : localisation, contacts,
crash logs, diagnostics, historique web, apps installées, santé, calendrier.
⚠️ Les données des **locataires** (tiers saisis par le bailleur) comptent
comme données collectées — elles sont couvertes par les lignes ci-dessus.

---

## 2. App Store Connect

### 2.1 App Privacy (labels) — section « Data Types »

Réponse globale : **« Yes, we collect data from this app »**.
Pour chaque type : **Linked to the user = Yes** · **Used for tracking = No**
· Purpose = **App Functionality**.

| Type Apple | Contenu Baillan |
|---|---|
| Contact Info → Name / Email Address / Phone Number / Physical Address | Profil bailleur + locataires + adresses des biens |
| Financial Info → Other Financial Info | Loyers, paiements, dépôts de garantie |
| User Content → Photos or Videos | Images uploadées (justificatifs) |
| User Content → Other User Content | Baux, quittances PDF, documents |
| User Content → Customer Support | Formulaire « Nous contacter » |
| Identifiers → User ID | UID Firebase Auth + installation ID |

Rien dans : Location, Browsing/Search History, Diagnostics, Usage Data
(pas d'Analytics/Crashlytics), Purchases 🔁 FEAT-044.
Privacy policy URL : `https://easy-rent-54cd4.web.app/privacy`.

### 2.2 Questionnaire d'âge (système 2026)
- Violence, contenu sexuel, jeux d'argent, substances, horreur : **None**
- Création de compte : **Oui** (sans restriction d'âge technique)
- Accès web non filtré : **Non** (les liens sortent vers le navigateur)
- Contenu généré par les utilisateurs visible par d'autres : **Non**
- Résultat attendu : **4+** (13+ acceptable selon pondération compte)

### 2.3 App Review Information
- Sign-in required : **Oui** → identifiants du compte démo (§3)
- Notes (anglais) : réutiliser le bloc du §1.3 tel quel
- Contact : téléphone + email joignables pendant la review

### 2.4 Export compliance
- Déjà traité dans le binaire : `ITSAppUsesNonExemptEncryption=false`
  (Info.plist) → App Store Connect ne posera plus la question à chaque build
- **Déclaration France** : position documentée dans
  [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) §2 (zone grise gRPC/BoringSSL ;
  risque zéro = déclaration simplifiée ANSSI, gratuite, une seule fois)

---

## 3. Compte démo review (à créer avant de remplir 1.3 et 2.3)

Exigences : valide **en permanence**, réutilisable, sans OTP/2FA, données
représentatives. Recette (~10 min, via l'app web ou mobile) :

1. Créer le compte email/password : `review.stores@<domaine>` + mot de passe
   dédié robuste (il sera lisible par les équipes de review des deux stores
   — ne JAMAIS réutiliser un mot de passe existant).
2. Se connecter et saisir : **1 bien** (adresse réaliste fictive), **1
   locataire** (nom/email fictifs), **1 bail actif** (loyer + charges),
   **2 paiements** enregistrés, **1 quittance générée** (PDF visible).
3. Ajouter **1 document** uploadé (PDF quelconque) et **1 dépense**
   (facture fictive) pour couvrir FEAT-041.
4. Vérifier la connexion depuis un appareil « neuf » (navigation privée) :
   pas d'étape supplémentaire, pas de vérification email bloquante.
5. Consigner les identifiants dans le gestionnaire de mots de passe +
   les coller dans Play Console (App access) et App Store Connect
   (App Review Information).

⚠️ Ce compte vit dans le projet Firebase de prod : le marquer clairement
(`fullName: "Compte Démo Review"`) et l'exclure de toute stat métier future.

---

## 4. Ordre de remplissage recommandé

1. Créer le compte démo (§3) — prérequis des deux consoles.
2. Play Console : dérouler §1.1 → §1.8 dans l'ordre (tout est bloquant).
3. App Store Connect : §2.1 → §2.3 (le §2.4 est déjà réglé côté binaire).
4. Revenir à [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) §6 pour la suite
   (DSA trader, signing, closed testing Play).

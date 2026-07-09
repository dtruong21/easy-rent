# Checklist de lancement stores — semaine du 13/07/2026

> **But** : checklist opérationnelle, ordonnée par dépendances, pour passer de
> « code prêt » à « app soumise » sur Google Play et l'App Store.
> Compagnon d'exécution de [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) (le
> *pourquoi* + sources) — ici c'est le *quoi/dans quel ordre/à cocher*.
>
> **Rappel fiabilité** (cf. en-tête `STORE_COMPLIANCE.md`) : les axes
> « politiques Play » et « UE/France » sont sourcés mais **non contre-vérifiés**.
> Re-valider chaque valeur datée au moment de remplir les consoles.
>
> **État au 2026-07-09** : code review-bloquant ✅ (FEAT-045), AAB release signé
> ✅ (clé upload `CN=Baillan, O=Daki, C=FR`, `build/app/outputs/bundle/release/app-release.aab`, v1.0.0+1). Reste = comptes + DSA + formulaires + 2 tâches contenu.

---

## 🔁 Reprise (handoff 2026-07-09 — avant reformatage du PC)

**Où on en est :** FEAT-045 (suppression de compte) + i18n FR/EN sont **en prod**. La page `/legal` (mentions légales) et la privacy policy v1.3 sont sur `develop`/staging mais la **promotion `develop → main` a été volontairement RETENUE** : `lib/features/privacy/presentation/legal_page.dart` contient les mentions éditeur en placeholders `« à compléter »`.

**Pour reprendre (dans l'ordre) :**
1. Remplir les vraies mentions éditeur dans `legal_page.dart` (§1/§2 : dénomination, statut, SIREN/SIRET, adresse, email, téléphone, directeur de publication) une fois le micro-entrepreneur immatriculé, retirer le bandeau « brouillon ».
2. PR → `develop` → contrôle sur staging.
3. Promouvoir `develop → main` (⚠️ **auto-déploie le web en prod**, Firebase live, via `deploy.yml`).
4. Dérouler §2→§6 ci-dessous (comptes, DSA, formulaires, uploads).

**⛔ AVANT DE FORMATER CE PC — sauvegardes hors git (git ne les contient pas) :**
- **Clé d'upload Android** `~/keystores/baillan/` (`upload-keystore.jks` + `key.properties`) : **JAMAIS commitée** (secret). **La sauvegarder** (gestionnaire de mots de passe / disque chiffré) — sa perte = **impossible de mettre à jour l'app sur Play, définitivement**.
- Éventuellement le dossier mémoire Claude `~/.claude/…/memory/` (les points de reprise ; l'essentiel est aussi ici en git).

**Sur le nouveau PC :** cloner le repo, installer Flutter (`~/Documents/flutter/bin`), restaurer la clé d'upload puis `cp ~/keystores/baillan/key.properties android/`, `firebase login`. Tout le code + docs sont sur `origin` (rien à récupérer localement).

---

## 0. Décisions à trancher AVANT de commencer (gèlent le reste)

- [ ] **Type de compte Play** : **organisation** (D-U-N-S requis) *ou* personnel.
  - Organisation → **exempte du test fermé 12 testeurs × 14 j** et simplifie le DSA trader. **Recommandé** si tu veux publier vite.
  - Personnel (créé après 13/11/2023) → impose 12 testeurs × 14 jours continus avant l'accès production (~3-4 semaines de calendrier).
- [ ] **Statut DSA** : trader vs non-trader pour la V1 (gratuite, sans IAP).
  - Non-trader défendable en V1, **mais** FEAT-044 (freemium) forcera trader → re-déclaration. Reco : **créer un micro-entrepreneur (SIREN)** + coordonnées dédiées **dès maintenant** pour ne le faire qu'une fois.
- [ ] **Coordonnées « trader » dédiées** : email + téléphone + adresse postale (boîte postale acceptée par Apple). Elles seront **publiées** sur les deux fiches (27 pays UE).
- [ ] **Déclaration chiffrement France (App Store)** : rester « exempt » (pratique courante) ou faire la déclaration simplifiée **ANSSI** (gratuite, une fois). Non bloquant pour la review — décision de risque.
- [ ] **Pays de distribution** (France + reste UE ? monde ?) et **prix** (gratuit en V1).

---

## 1. Tâches CODE encore ouvertes (bloquent la soumission, à faire par le dev)

> Ce ne sont pas des formulaires console mais elles gâtent la release — à
> boucler en parallèle de l'admin. *(Claude peut les implémenter sur demande.)*

- [ ] **Page `/legal` — mentions légales LCEN** (art. 1-1, loi 2004-575) : identité éditeur + hébergeur, accessible depuis Profil. Hors review stores mais **obligation légale FR** (sanction pénale possible). → route publique `/legal` + tuile hub Profil.
- [ ] **Privacy policy — § « données de tiers (locataires) »** : le bailleur est responsable de traitement, Baillan = outil (Google/Firebase sous-traitant), rappeler le devoir d'information des locataires. Cohérent avec le §5 de `STORE_COMPLIANCE.md`.
- [ ] **Compte de démo « review »** : `review@…` avec données seedées (**1 bien, 1 locataire, 1 bail, quelques paiements, 1 quittance**) — servira à *App access* (Play) et *App Review sign-in* (Apple). Identifiants valides en permanence, instructions **en anglais**.

---

## 2. Comptes & signing (lead time — lancer en tout premier)

### 2.1 Comptes développeur
- [ ] **Apple Developer Program** — inscription (99 $/an), vérification d'identité (délai possible de quelques jours). Requis pour signer **et** pour Sign in with Apple.
- [ ] **Google Play Developer** — compte créé/vérifié (frais unique 25 $). Type = décision §0.
- [ ] Si organisation : obtenir le **D-U-N-S** (Apple) / vérif entreprise (Play).

### 2.2 Signing Android
- [x] AAB release signé avec la clé upload Baillan (fait le 2026-07-09).
- [ ] **Play App Signing** : à l'upload du 1er AAB, laisser Google gérer la *app signing key* (notre clé `upload` ne sert qu'à signer les uploads). Conserver `~/keystores/baillan/upload-keystore.jks` + `key.properties` en lieu sûr (perte = impossible d'updater).
- [ ] ⚠️ **SHA Google Sign-In** : ajouter dans **Firebase → app Android** :
  - le **SHA-1/SHA-256 de la clé `upload`** (`keytool -list -v -keystore ~/keystores/baillan/upload-keystore.jks -alias upload`), **et**
  - le **SHA-1/SHA-256 de la clé *App Signing* générée par Play** (Play Console → *App integrity* → *App signing*).
  - Sans le SHA **Play App Signing**, Google Sign-In **casse en production** (piège classique). Re-télécharger `google-services.json` après ajout.

### 2.3 Signing iOS
- [ ] Dans Xcode : renseigner le **`DEVELOPMENT_TEAM`** (signature *Automatic* actuellement sans team → ne peut pas archiver).
- [ ] Certificat de distribution + **provisioning profile** App Store pour `com.daki.baillan`.
- [ ] Activer la capability **Sign in with Apple** (App ID Apple Developer + Xcode).
- [ ] Configurer le provider **Apple** dans Firebase Auth (Services ID / clé / Team ID) pour que SIWA fonctionne sur le build signé.

---

## 3. DSA trader status — 🔴 bloquant UE (identité à vérifier → lead time)

- [ ] **Play Console → Business information** : déclarer le statut trader, vérifier identité/adresse. Publié dans « About the developer ».
- [ ] **App Store Connect → Business → EU DSA trader** : renseigner adresse (BP OK) / téléphone / email vérifiés. Publiés dans les 27 pays UE.
- [ ] Sans ces déclarations vérifiées : **pas de distribution UE** sur l'un ni l'autre.

---

## 4. Google Play — formulaires (utiliser les tables du §5 de STORE_COMPLIANCE)

### 4.1 Création & fiche
- [ ] Créer l'app : nom **« Baillan. »**, langue par défaut **FR**, type = app (pas jeu), gratuite.
- [ ] **Store listing** : titre, description courte + longue, **captures téléphone + tablette**, icône, feature graphic.
- [ ] **Countries / pricing** : gratuit, sélectionner les pays (§0).

### 4.2 App content / déclarations *(tout bloquant si incomplet)*
- [ ] **Privacy policy URL** (privacy policy v1.3 + § données de tiers).
- [ ] **Data safety** (support 10787469) : remplir avec la table §5 — données bailleur **et locataires** collectées, *Sharing = none*, chiffrement en transit (TLS), suppression disponible. **Déclarer l'URL de suppression** `https://easy-rent-54cd4.web.app/delete-account`.
- [ ] **App access** (9859455) : fournir le **compte démo review** + instructions EN (§1).
- [ ] **Financial features** (13849271) : cocher **« no financial features »** (Baillan *suit* des loyers, n'octroie pas de crédit, ne traite aucun paiement — le futur IAP FEAT-044 n'y change rien).
- [ ] **Ads** = No.
- [ ] **Content rating** : questionnaire IARC (résultat attendu 3+).
- [ ] **Target audience** = **18+** (hors politique Families).
- [ ] **News / Government / Health** = No.
- [ ] **Permissions** : aucune permission sensible — ne **jamais** déclarer `READ_CONTACTS`.

### 4.3 Release technique
- [ ] Upload de l'**AAB** sur **Internal testing** d'abord.
- [ ] ⚠️ Contrôler l'absence d'**avertissement pages 16 KB** au 1er upload (libs natives Firebase/pdf). Flutter 3.41 probablement OK, à confirmer.
- [ ] Si **compte perso** : lancer le **closed testing 12 testeurs × 14 jours continus**, puis le questionnaire d'accès production (≈ 3-4 semaines).

---

## 5. App Store Connect — formulaires

### 5.1 Création & fiche
- [ ] Créer l'app : bundle ID **`com.daki.baillan`**, nom, langue primaire **FR**, SKU.
- [ ] **Captures d'écran** aux tailles requises (iPhone + iPad).
- [ ] **Pricing & availability** : gratuit, pays (§0).

### 5.2 Déclarations
- [ ] **App Privacy (nutrition labels)** : table §5 — tout ce qui part vers Firestore = *collected* (y c. données locataires), **Tracking = No** (pas d'ATT).
- [ ] **Questionnaire d'âge 2026** (tranches iOS 26) : app utilitaire, résultat attendu 4+/13+.
- [ ] **Export compliance** : `ITSAppUsesNonExemptEncryption=false` ✅ (US exempt). France = décision §0 (ANSSI optionnelle).
- [ ] **App Review sign-in info** : renseigner le **compte démo review** + note « Sign in with Apple présent au même niveau que Google ».

### 5.3 Premier upload
- [ ] Archive + upload **TestFlight** (Xcode 26.6 OK, SDK iOS 26 requis depuis 28/04/2026).
- [ ] ⚠️ Surveiller les mails **ITMS-91053 / ITMS-91061** (privacy manifests app + SDKs tiers). Pods Firebase récents embarquent les manifests — contrôler au 1er upload.

---

## 6. Soumission finale

- [ ] **Play** : une fois testing satisfait (+ accès production si compte perso) → promouvoir vers **Production**, soumettre.
- [ ] **App Store** : build TestFlight validé → soumettre pour **App Review** (rappel 4.8 : bouton Apple iso Google ; 5.1.1(v) : suppression + révocation token Apple ✅ FEAT-045).

---

## Ordre conseillé sur la semaine

1. **Lun 13** : décisions §0 + créer/vérifier les 2 comptes dev + micro-entrepreneur/coordonnées trader (§2.1). Lancer en parallèle les tâches CODE §1.
2. **Mar 14** : DSA trader des deux côtés (§3, vérif identité = lead time). Signing iOS (§2.3) + SHA Firebase (§2.2).
3. **Mer 15** : formulaires Play (§4) + 1er upload AAB internal testing. Si compte perso → **démarrer le closed testing** (le chrono de 14 j court).
4. **Jeu 16** : formulaires App Store (§5) + upload TestFlight.
5. **Ven 17** : QA sur devices réels (login email/Google/Apple, suppression compte, quittances), corrections. Soumission Apple possible ; **Play en attente** du closed testing si compte perso.

> **Calendrier réaliste** : avec un **compte Play organisation**, la prod peut
> partir dès la semaine du 13/07. Avec un **compte perso**, la prod Play est
> ~3-4 semaines plus loin (closed testing) — l'App Store, lui, n'a pas cette
> contrainte.

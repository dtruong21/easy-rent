# Conformité stores — Google Play & Apple App Store (FEAT-024)

> Audit réalisé le **2026-07-07** (recherche web multi-agents, sources
> officielles citées par item). Fiabilité : les axes **« target API Android »**
> et **« App Store Review »** ont été contre-vérifiés par un second agent ;
> les axes **« politiques Play »** et **« UE/France »** sont sourcés mais
> **non contre-vérifiés** (limite de budget) — re-valider chaque valeur datée
> au moment du remplissage des consoles.

## TL;DR — verdict pour une release production

**Le code et la config sont quasi prêts** (target API ✅, privacy manifest ✅,
export compliance ✅, Xcode 26 ✅). Les vrais bloquants sont **fonctionnels et
administratifs** :

| # | Bloquant | Stores | Nature |
|---|---|---|---|
| 1 | ✅ **Suppression de compte in-app** + page web publique de demande | Play **et** App Store | **Livré (FEAT-045, 2026-07-07)** — reste à déclarer l'URL `/delete-account` dans Data safety (§5) |
| 2 | 🔴 **Formulaires consoles** : Data safety, App access (compte démo), Financial features, Privacy labels, questionnaire d'âge | Play + App Store | Administratif (tables pré-remplies §5) |
| 3 | 🔴 **DSA « trader status »** (UE) — coordonnées vérifiées et **publiées** sur les fiches | Play + App Store | Administratif + décision (perso vs orga) |
| 4 | 🟠 **Compte Play personnel nouveau** : test fermé **12 testeurs × 14 jours** avant l'accès production | Play | Calendrier (~3-4 semaines) |
| 5 | 🟠 **Mentions légales LCEN** (page éditeur/hébergeur) | Obligation légale FR, hors review | Contenu à créer |
| 6 | 🟠 **Signing release** (keystore Android + Apple Developer Program) | Play + App Store | Déjà tracké dans [MOBILE.md](MOBILE.md) |

**SDK 37 : rien à faire.** Android 17 (API 37, sorti le 16/06/2026) ne sera
exigé que vers **août 2027**. `targetSdk 36` actuel est conforme dès
aujourd'hui et après la deadline du 31/08/2026 (§1.1).

---

## 1. Android / Google Play

### 1.1 Target API level et SDK 37 ✅ *(contre-vérifié)*

| Point | Statut Baillan |
|---|---|
| Exigence au **31/08/2026** : nouvelles apps et mises à jour doivent cibler **API 36** (Android 16) | ✅ `targetSdk 36` / `compileSdk 36` (défauts Flutter 3.41) — conforme aujourd'hui et après la deadline |
| **SDK 37 = Android 17** « Cinnamon Bun », stable depuis le **16/06/2026** | ✅ Aucune action : target 37 attendu obligatoire vers le **31/08/2027** (extrapolation de la politique glissante, date non publiée). Bump prévu S1 2027, idéalement via upgrade Flutter |
| `minSdk 24` | ✅ Play ne régule pas minSdk |
| ⚠️ Behavior change Android 17 à anticiper pour le bump 2027 | Sur grands écrans (≥ 600dp), les apps ciblant l'API 37 **ne peuvent plus verrouiller l'orientation ni refuser le resize** (`screenOrientation`, `resizeableActivity`, `min/maxAspectRatio` ignorés). Baillan ne verrouille rien aujourd'hui → OK, à re-vérifier au bump |

Sources : [target-sdk requirements](https://developer.android.com/google/play/requirements/target-sdk) · [support 11926878](https://support.google.com/googleplay/android-developer/answer/11926878) · [Android 17 release notes](https://developer.android.com/about/versions/17/release-notes)

### 1.2 Pages mémoire 16 KB ⚠️ *(contre-vérifié — à vérifier au 1er AAB)*

Depuis le **01/11/2025** (extension expirée le 31/05/2026), tout upload ciblant
API 35+ doit supporter les pages 16 KB sur appareils 64 bits — le Play Console
**bloque** sinon. Flutter ≥ 3.24 (NDK r28) produit des binaires conformes ;
notre 3.41 est très probablement OK, **mais** contrôler au premier upload AAB
l'absence d'avertissement 16 KB (libs natives des plugins Firebase/pdf).
Source : [page-sizes](https://developer.android.com/guide/practices/page-sizes)

### 1.3 Politiques Play *(sourcé, non contre-vérifié)*

| Exigence | Statut | Action |
|---|---|---|
| **Suppression de compte** : chemin in-app **+ URL web** de demande (sans réinstaller), déclarés dans Data safety ([13327111](https://support.google.com/googleplay/android-developer/answer/13327111)) | ✅ **fait (FEAT-045)** | Écran Profil → « Supprimer mon compte » (re-auth fraîche + callable `deleteAccount` : purge Firestore + Storage + Auth ; rétention 5 ans des quittances loi 6/07/1989 **annoncée dans le flux** + privacy policy v1.2) + page publique `https://easy-rent-54cd4.web.app/delete-account` (l'essai anonyme s'y supprime directement). Reste : déclarer cette URL dans le formulaire Data safety |
| **Data safety form** ([10787469](https://support.google.com/googleplay/android-developer/answer/10787469)) | 🔴 formulaire | Pré-rempli §5 — inclut les **données de tiers (locataires)** |
| **Test fermé nouveaux comptes perso** (créés après le 13/11/2023) : ≥ **12 testeurs opt-in 14 jours continus**, puis questionnaire d'accès production ([14151465](https://support.google.com/googleplay/android-developer/answer/14151465)) | 🟠 à vérifier | Si compte perso nouveau → prévoir 3-4 semaines. Comptes **organisation exemptés** (D-U-N-S requis) |
| **App access** : identifiants de démo valides en permanence, instructions en anglais ([9859455](https://support.google.com/googleplay/android-developer/answer/9859455)) | 🔴 formulaire | Créer un compte `review@…` avec données de démo (1 bien, 1 locataire, 1 bail, paiements, 1 quittance) |
| **Financial features declaration** — obligatoire pour toutes les apps ([13849271](https://support.google.com/googleplay/android-developer/answer/13849271)) | 🔴 formulaire | Cocher « no financial features » : Baillan **suit** des loyers, n'octroie pas de crédit et ne traite aucun paiement. Le futur IAP FEAT-044 ne change rien |
| Politique **UGC** ([9876937](https://support.google.com/googleplay/android-developer/answer/9876937)) | ✅ n/a | Support privé 1:1, données visibles par leur seul propriétaire |
| **Permissions** (+ politique contacts/localisation d'avril 2026) | ✅ ok | Aucune permission sensible. Ne jamais déclarer `READ_CONTACTS` (utiliser le Contact Picker si besoin un jour) ; photo picker pour les uploads |
| Autres déclarations App content : privacy policy URL, ads = non, IARC (attendu 3+), target audience **18+** (hors politique Families), government/health/news = non | 🔴 formulaires | Mécanique, tout est bloquant si incomplet |
| **Release technique** : AAB signé release (`flutter build appbundle`) + Play App Signing | 🟠 gap connu | Tracké dans [MOBILE.md](MOBILE.md) (le template signe encore en debug) |
| **Android Developer Verification** (programme d'identité, enforcement France attendu 2027) | ✅ radar | Rien à faire pour 2026 |

## 2. iOS / App Store *(contre-vérifié)*

| Exigence | Statut | Action |
|---|---|---|
| **5.1.1(v) Suppression de compte in-app** (depuis 30/06/2022) — la désactivation ne suffit pas ; pas de « contactez le support » ; **révoquer les tokens Sign in with Apple** (API REST `/auth/revoke`, exposée par Firebase Auth `revokeToken`) ([doc officielle](https://developer.apple.com/support/offering-account-deletion-in-your-app/)) | ✅ **fait (FEAT-045)** | Flux unique web/iOS/Android couvrant email/password, Google, Apple **et** anonymes ; token Apple révoqué via `revokeTokenWithAuthorizationCode` (authorizationCode issu de la re-auth — effectif sur iOS/macOS, best-effort ailleurs) ; mention rétention quittances affichée dans le flux |
| **4.8 Login Services** : Google Sign-In ⇒ une option équivalente préservant la vie privée obligatoire ([guidelines#login-services](https://developer.apple.com/app-store/review/guidelines/#login-services)) | ✅ prévu | Sign in with Apple déjà iso web — bouton Apple **au même niveau** que Google sur iOS |
| **Privacy manifest de l'app** (bloque l'upload depuis le 01/05/2024, erreur ITMS-91053) ([doc](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)) | ✅ **fait** | `ios/Runner/PrivacyInfo.xcprivacy` créé, enregistré dans Xcode, embarqué dans Runner.app (vérifié au build) |
| **Privacy manifests des SDKs tiers** (rejet ITMS-91061 depuis le 12/02/2025) — Firebase*, Flutter, shared_preferences… sont sur la [liste officielle](https://developer.apple.com/support/third-party-SDK-requirements/) | ⚠️ à vérifier | Pods récents (firebase-ios-sdk ≥ 10.22 embarque les manifests). Contrôler les mails ITMS-9105x au premier upload TestFlight |
| **App Privacy labels** (App Store Connect) ([app-privacy-details](https://developer.apple.com/app-store/app-privacy-details/)) | 🔴 formulaire | Pré-rempli §5 — tout ce qui part vers Firestore est « collected », **y compris les données locataires** |
| **SDK de build** : depuis le **28/04/2026**, upload = Xcode 26 / SDK iOS 26 minimum ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)) | ✅ ok | Xcode 26.6 sur la machine. Deployment target iOS 13 inchangé. Tester les surfaces natives (style Liquid Glass) : alerts, share sheet, SIWA |
| **Export compliance US** : chiffrement standard (HTTPS/TLS) → exempt | ✅ **fait** | `ITSAppUsesNonExemptEncryption = false` dans Info.plist |
| **Déclaration chiffrement France** : gRPC/BoringSSL de Firestore = TLS standard **non fourni par l'OS** → lecture stricte = formulaire français App Store Connect ; pratique répandue de l'écosystème = exempt ([table officielle](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)) | ⚠️ à trancher | Décision utilisateur. Risque zéro = déclaration simplifiée ANSSI (gratuite, une fois). Non bloquant en pratique pour la review |
| **Questionnaire d'âge 2026** (système refondu, tranches iOS 26) | 🔴 formulaire | Dans le flux de soumission — app utilitaire, résultat attendu 4+/13+ |
| **Apple Developer Program** + capability Sign in with Apple | 🟠 gap connu | Tracké dans [MOBILE.md](MOBILE.md) (99 $/an, requis pour signer et pour SIWA) |

## 3. UE / France *(sourcé, non contre-vérifié)*

| Obligation | Statut | Détail |
|---|---|---|
| **DSA trader status — App Store** (enforcement depuis le 17/02/2025) | 🔴 bloquant | Sans déclaration vérifiée, pas de distribution UE. Coordonnées (adresse — boîte postale acceptée par Apple —, téléphone, email) **publiées** sur la fiche dans les 27 pays UE ([doc ASC](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)) |
| **DSA trader status — Play** | 🔴 bloquant | Même exigence dans Play Console (Business information), vérification identité/adresse ; infos publiées dans « About the developer » |
| Statut **non-trader** possible en V1 ? | ⚠️ décision | V1 gratuite sans IAP → non-trader défendable. **Mais** FEAT-044 (freemium) imposera le statut trader → re-vérification. Recommandation : créer un **micro-entrepreneur (SIREN)** + email/téléphone/adresse dédiés dès maintenant, et envisager un **compte Play organisation** (supprime aussi l'exigence 12 testeurs × 14 j) |
| **Mentions légales LCEN** (art. 1-1, loi 2004-575) : identité éditeur + hébergeur accessibles depuis l'app | 🟠 gap légal | Hors review stores mais sanction pénale possible. Créer une page « Mentions légales » (route `/legal`) liée depuis Profil, avant release |
| **Médiation de la consommation** (art. L612-1 c. conso) | ✅ plus tard | Non requis tant que l'app est 100 % gratuite. **Obligatoire avant FEAT-044** (adhésion médiateur ~200-400 €/an + CGV) |
| **European Accessibility Act** (28/06/2025) | ✅ exempté | Exemption micro-entreprise (< 10 salariés, < 2 M€ CA). Bonnes pratiques WCAG conservées |
| **RGPD — données de tiers (locataires)** | 🟠 contenu | Compléter la privacy policy : le bailleur est responsable de traitement des données de ses locataires, Baillan fournit l'outil (Google/Firebase sous-traitant) ; rappeler le devoir d'information des locataires. Cohérent avec les déclarations §5 |

## 4. SDK 37 — position officielle Baillan

- **Aujourd'hui : rien à changer.** `targetSdk 36` satisfait la deadline Play
  du 31/08/2026 ; l'API 37 ne sera exigée que vers **août 2027**.
- **S1 2027** : bump `targetSdk`/`compileSdk` 37 via upgrade Flutter, en
  vérifiant le behavior change **grands écrans** (orientation/resize forcés
  sur ≥ 600dp — notre shell adaptatif NavigationRail est déjà compatible).
- SDK 37 est installé sur la machine de dev (`android-37.0`) — utile pour
  tester en avance, inutile pour publier.

## 5. Déclarations de données pré-remplies

Tout ce qui est écrit dans Firestore est « collecté » au sens des deux stores,
**y compris les données de tiers (locataires) saisies par le bailleur**.
Aucun partage à des tiers, aucun tracking publicitaire, chiffrement en transit
(TLS), suppression possible (post FEAT-045).

| Donnée | Play Data safety | Apple Privacy label | Notes |
|---|---|---|---|
| Nom, email, téléphone, adresse (bailleur **et** locataires) | Personal info → Name / Email / Phone / Address | Contact Info (Linked to you) | Purpose : App functionality + Account management |
| Loyers, paiements, dépôts | Financial info → **Other financial info** | Financial Info → Other Financial Info | **Pas** « Payment info » : aucun paiement traité en V1 |
| Baux, quittances PDF, documents uploadés | Files and docs (+ Photos si photos de biens) | User Content → Other User Content | Rétention légale quittances 5 ans à mentionner |
| Demandes de support | App activity → Other user-generated content | User Content → Customer Support | — |
| UID Firebase Auth, Firebase installation IDs | Device or other IDs | Identifiers → User ID | Cf. [Privacy disclosures Firebase](https://firebase.google.com/docs/ios/app-store-data-collection) |
| Crash data / analytics | — (rien tant que Crashlytics/Analytics non intégrés) | — | Ne rien déclarer tant que non activé |
| Tracking / partage tiers | Shared = none | Tracking = **No** (pas d'ATT) | Pas de pub, pas de data broker |

## 6. Plan d'action ordonné avant la première release

> 📋 Checklist d'exécution ordonnée (semaine du 13/07) :
> [`STORE_LAUNCH_CHECKLIST.md`](STORE_LAUNCH_CHECKLIST.md).

1. **Code** (bloquants review) : ✅ **FEAT-045 suppression de compte in-app
   livrée (2026-07-07)** — purge Auth + Firestore + Storage (callable
   `deleteAccount`), révocation token Apple, mention rétention quittances,
   page web `/delete-account`, privacy policy v1.2. **Restent** : page
   `/legal` (mentions LCEN) + § « données de tiers » dans la privacy policy.
2. **Comptes & administratif** : type de compte Play (perso vs **organisation**
   — exempte du test fermé), Apple Developer Program, déclaration **DSA
   trader** des deux côtés (coordonnées dédiées, reco micro-entrepreneur).
3. **Signing release** : keystore + Play App Signing ; certificat/profil
   Apple + capability Sign in with Apple ; SHA-1 release dans Firebase.
4. **Formulaires consoles** avec les tables du §5 (Data safety, labels,
   App access avec compte démo, Financial features = none, âge, IARC).
5. **Play si compte perso** : closed testing 12 testeurs × 14 jours →
   demande d'accès production.
6. **Premier upload** : TestFlight (surveiller ITMS-91053/91061) + AAB
   (surveiller l'avertissement 16 KB).

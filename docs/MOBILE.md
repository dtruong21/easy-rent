# FEAT-024 — App mobile iOS/Android (préparation)

> Audit réalisé le 2026-07-03 (commit b699cb0) pour préparer le développement
> de la version mobile la semaine du 6 juillet 2026. Le codebase Flutter
> actuel (web) vise iOS et Android **sans réécriture** — même code, mêmes
> rules Firestore, mêmes Cloud Functions.

## ✅ Setup réalisé (2026-07-06)

Décisions actées :

| # | Décision | Choix |
|---|---|---|
| 1 | Bundle ID / applicationId | **`com.daki.baillan`** (définitif stores) |
| 2 | Cibles V1 | iOS + Android d'emblée |
| 3 | Distribution de test | différée (builds debug émulateur/simulateur) |
| 4 | Logins sociaux V1 | Google + Apple iso web (`signInWithProvider`) |
| 5 | minSdk / iOS minimum | défauts Flutter 3.41 (minSdk 24 / iOS 13) |
| 6 | Shell nav FEAT-026 | déjà mergé avant J1 ✅ |

Réalisé :

- `flutter create --platforms=android,ios` — dossiers `android/` + `ios/`
  (applicationId/bundle ID `com.daki.baillan`, label « Baillan. »).
- Apps Android + iOS enregistrées dans Firebase (`easy-rent-54cd4`) via
  `flutterfire configure` — `firebase_options.dart` couvre web/android/ios,
  `google-services.json` + `GoogleService-Info.plist` générés (clés publiques
  par design, committées — cf. `docs/SECURITY.md`).
- SHA-1/SHA-256 **debug** enregistrées sur l'app Android Firebase.
- URL schemes OAuth iOS (REVERSED_CLIENT_ID + app ID encodé) dans Info.plist.
- Auth : `_signInWithOAuthProvider` / `_defaultLinkWithProvider` — popup sur
  web, flux natif `signInWithProvider`/`linkWithProvider` sur mobile ; codes
  d'annulation mobile (`web-context-canceled`/`cancelled`) mappés en FR.
- Liens email (verify + reset password) : fallback `Env.publicAppUrl`
  (dart-define `APP_PUBLIC_URL`, défaut `https://easy-rent-54cd4.web.app`)
  quand `Uri.base.origin` n'existe pas (mobile).
- Partage quittances/régularisations : `web_share_service_io.dart` —
  `share_plus` (share sheet natif, PDF en pièce jointe, annulation
  détectée via `ShareResultStatus.dismissed`) sur
  Android/iOS ; no-op inchangé sur VM tests/desktop.
- `<queries>` Android 11+ (https + mailto) pour `url_launcher`.
- **Conformité stores (2026-07-07)** : `PrivacyInfo.xcprivacy` (privacy
  manifest app, exigence Apple 05/2024) créé et embarqué dans Runner.app ;
  `ITSAppUsesNonExemptEncryption=false` dans Info.plist. **Audit complet
  Play + App Store + UE/France : [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md).**

Reste à faire (itérations suivantes) :

- **🔴 Bloquants review stores** (détail + plan d'action ordonné dans
  [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md)) — ✅ suppression de compte
  in-app + page web `/delete-account` **livrées (FEAT-045, 2026-07-07)** ;
  restent : page `/legal` (mentions LCEN), formulaires consoles (Data
  safety — y déclarer l'URL `/delete-account` —, privacy labels, App
  access, Financial features, âge), déclaration DSA trader, test fermé Play
  12 testeurs × 14 j si compte perso nouveau.
- **Signing release** : keystore Android + certificat/profil Apple Developer,
  puis SHA-1 release à ajouter dans Firebase.
- **Apple Sign-In iOS** : capability « Sign in with Apple » (nécessite compte
  Apple Developer payant) — jusque-là, tester Google + email sur device.
  **QA device dédiée (audit FEAT-045 L2)** : vérifier que la re-auth Apple du
  flux de suppression fournit bien un `authorizationCode`
  (`additionalUserInfo`) et que `revokeTokenWithAuthorizationCode` révoque
  réellement (Réglages iOS → Apple ID → Connexion et sécurité) — la
  révocation est best-effort dans le code, exigée par la 5.1.1(v).
- **Icônes natives** : ✅ **faites (2026-07-08)** — icône launcher Baillan
  (B sérif italique crème sur fond encre + filet sauge) sur iOS **et** Android,
  générées par `flutter_launcher_icons` (config dans `pubspec.yaml`) depuis un
  master unique 1024 (`assets/icon/baillan_icon_master.png`, opaque pour l'App
  Store) + un foreground adaptatif Android (`baillan_icon_foreground.png`,
  fond encre `#1B1A17`). Le master est lui-même reproductible depuis la marque :
  `python3 tool/branding/generate_app_icons.py` (rend le « B » via
  `assets/fonts/EBGaramond-Italic.ttf`). Régénérer les icônes :
  `dart run flutter_launcher_icons`. **web/icons/ non touché.**
- **Splash natif** : ✅ **fait (2026-07-08)** — écran de lancement natif Baillan
  ADAPTATIF clair/sombre (suit l'apparence système, le splash étant peint avant
  Flutter), généré par `flutter_native_splash` (config dans `pubspec.yaml`,
  Android + iOS + Android 12+ SplashScreen). Clair : fond papier `#F7F4ED` + « B »
  encre (paraphe olive) ; sombre : fond encre `#1B1A17` + « B » crème (paraphe
  sauge) — cohérent avec le fond de chargement `web/index.html`, le scaffold et
  la tuile d'icône. Glyphes = `assets/splash/baillan_glyph_{ink,cream}.png`
  (marque dans le cercle safe 768 px d'Android 12), régénérés par
  `tool/branding/generate_app_icons.py`. Régénérer :
  `dart run flutter_native_splash:create`. `web:false` → splash web non touché.
- **Rapport d'incident (Crashlytics)** : ✅ **fait (2026-07-09)** — Firebase
  Crashlytics **mobile uniquement** (pas de support web ; `firebase_crashlytics`
  ^4.3.10, gardé par `kIsWeb`), collecte **opt-in RGPD désactivée par défaut**.
  Consentement via Profil → Confidentialité (`crashReportingProvider` +
  `lib/core/observability/`), défauts natifs OFF (`AndroidManifest` +
  `Info.plist`). Gradle : plugin Crashlytics **2.9.9** (la 3.x exige
  google-services ≥ 4.4.1 ; on garde 4.3.15). PdC v1.3 + `rgpdConsentVersion`
  bumpé v3-2026-07 + STORE_COMPLIANCE §5 (Diagnostics/Crash Data, opt-in).
  **Suites (non bloquantes)** : (1) build phase iOS de symbolication dSYM
  (`${PODS_ROOT}/FirebaseCrashlytics/run`) — différée (les erreurs Dart
  remontent avec leur stack ; à ajouter via Xcode UI) ; (2) vérifier
  `ios/Runner/PrivacyInfo.xcprivacy` (NSPrivacyCollectedDataTypes crash) au 1ᵉʳ
  upload TestFlight.
- **CI** : job build APK debug en PR (non bloquant), distribution différée.
- QA parcours métier complet sur devices réels (J4 du plan).
- **SDK 37 (Android 17)** : rien à faire avant ~août 2027 — targetSdk 36
  conforme (cf. [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) §1.1 et §4).

Build local :

```bash
flutter build apk --debug          # Android (APP_ENV=dev par défaut)
flutter build ios --simulator      # iOS simulateur (pas de codesign)
flutter run -d <device>            # run direct émulateur/simulateur
```

## Test Lab (Robo)

Build Android **debug** de test, lancé sur le Firebase Test Lab (Robo) contre la
base Firestore **`staging`** — jamais la prod. Détails d'architecture :
[`ENVIRONMENTS.md`](ENVIRONMENTS.md) (« Build de test mobile ») et ADR 0003
(amendement 2026-09-29).

**Prérequis**

- **Functions déployées avec le routage mobile par compte** (`dbForRequest`
  async, appels sans `Origin` routés par compte). Sans ce déploiement, les
  callables du build de test écrivent en prod.
- **Compte de test** semé par
  [`tool/seed/seed_testlab_staging.mjs`](../tool/seed/seed_testlab_staging.mjs)
  (à lancer soi-même, compte owner) :

  ```bash
  gcloud auth application-default login          # une fois
  node tool/seed/seed_testlab_staging.mjs --yes-staging
  ```

  Le script crée (ou reprend) le compte Auth `testlab.robo@example.com` (email
  marqué vérifié, mot de passe aléatoire renouvelé à chaque run), écrit son doc
  `landlords/{uid}` **uniquement** dans `staging` (profil complet, palier
  `paid`), crée un jeu de données réaliste via les vraies callables (routées vers
  `staging` par l'Origin de l'app web staging — marche **sans** le redéploiement
  des Functions) et remplit `dart-defines.testlab.json` (gitignoré ; le mot de
  passe n'est jamais affiché). Il **refuse** tout compte qui a un doc landlord en
  prod, avant d'y toucher. Rejouable : pas de nouveau seed si des biens existent.
  Vérifiable d'abord sur les émulateurs (mode décrit en tête du script).
  - Le doc `landlords/{uid}` doit exister dans `staging` **avant** de lancer
    Test Lab : s'il est absent, les callables mobiles retombent sur la prod.
  - **Email vérifié** obligatoire : le routeur de l'app ne laisse passer que les
    comptes non anonymes avec `emailVerified == true`
    (`auth_session_provider.dart`) ; sinon Robo reste bloqué sur l'écran de
    vérification. Le script le positionne.
  - **Ne jamais utiliser ce compte en prod** : le routage mobile cherche la prod
    d'abord, un compte présent dans les deux bases serait routé en prod.
  - **Mot de passe dédié** : les identifiants d'auto-login sont des constantes de
    compilation, lisibles dans l'APK debug (que Test Lab stocke dans le bucket du
    projet). Le script génère un mot de passe aléatoire propre à ce compte.

**Vérification préalable (smoke test) — avant le premier run Robo**

Après le déploiement des Functions : lancer le build de test (émulateur Android
ou appareil, **sans** `USE_FIREBASE_EMULATOR`), créer une entité (par ex. un
bien) et vérifier dans la console Firebase qu'elle apparaît dans la base
**`staging`** et **pas** dans `(default)`.
Tant que les Functions ne sont pas redéployées, les callables du build de test
écrivent encore en prod : **ne pas lancer Test Lab avant ce contrôle.**

**Build et lancement**

```bash
# 1. Dart-defines (fichier gitignoré) : écrit par le script de seed ci-dessus.
#    (À la main : cp dart-defines.testlab.example.json dart-defines.testlab.json
#     puis renseigner TEST_AUTO_LOGIN_EMAIL / _PASSWORD.)

# 2. Build APK debug
flutter build apk --debug --dart-define-from-file=dart-defines.testlab.json

# 3. Lancement Robo (modèles disponibles : gcloud firebase test android models list)
gcloud firebase test android run --type robo \
  --app build/app/outputs/flutter-apk/app-debug.apk \
  --device model=MediumPhone.arm,version=34 \
  --device model=Pixel2.arm,version=30 \
  --timeout 300s --project easy-rent-54cd4
```

**À savoir**

- `MOBILE_STAGING` et l'auto-login n'ont **aucun effet en release**
  (`kReleaseMode`) : le build de test est un APK debug, la release store n'est
  pas concernée.
- L'app se connecte seule au compte de test au démarrage et affiche un ruban
  violet « STAGING » (le ruban « EMULATOR » prime si l'émulateur est aussi actif ;
  dans ce cas l'auto-login est ignoré, le compte de test n'existant pas dans
  l'Auth local).
- **Risque Robo — écrans destructifs.** L'auto-login rend la session « récente » :
  Robo peut donc atteindre les écrans sensibles du compte (déconnexion,
  « Supprimer mon compte » — qui supprime l'utilisateur Auth **partagé** —,
  changement d'email ou de mot de passe). Reprise après incident : relancer
  `node tool/seed/seed_testlab_staging.mjs --yes-staging` (recrée le compte et
  réécrit `dart-defines.testlab.json`), puis reconstruire l'APK.
- **Comptes anonymes résiduels.** Les comptes anonymes que Robo pourrait créer ne
  sont pas nettoyés par `cleanup_expired_anon` (il ne scanne que `(default)`) :
  à purger à la main s'ils s'accumulent.
- Effet de bord d'un `flutter build apk` local : Flutter peut ajouter
  `android.builtInKotlin=false` et `android.newDsl=false` à
  `android/gradle.properties` — ne pas les committer (`git checkout android/gradle.properties`).

**Résultats** : console Firebase → Test Lab (plantages, captures, vidéo). Quota :
10 tests/jour sur le plan Spark ; sur le plan Blaze (le nôtre), un quota
quotidien gratuit en minutes d'appareil, puis facturation à l'usage — vérifier
la page Tarifs Firebase avant des campagnes répétées.

## TL;DR

Le codebase est **déjà largement portable** : les seuls points web-only sont
isolés derrière des bridges à imports conditionnels avec stubs, et toutes les
dépendances ont des implémentations mobiles. **Deux vrais chantiers de code** :
(1) le **shell de navigation adaptatif** (FEAT-026 — la nav actuelle en hub via
le dashboard est hostile au tactile ; à poser en prérequis, cf. ci-dessous) et
(2) **l'auth sociale** (`signInWithPopup` est web-only). Le reste est de la
configuration de plateforme (bundle ID, Firebase apps, signing).

> **Prérequis navigation — FEAT-026.** Avant/au tout début de la semaine mobile,
> on remplace le hub-dashboard par un **shell adaptatif** (`NavigationBar` <600px
> / `NavigationRail` ≥600px via `StatefulShellRoute.indexedStack`). Même
> structure web et mobile → la « passe UI mobile » (chantier n°7) se réduit à
> SafeArea + clavier + touch targets, sans navigation tactile à réinventer.
> Concept faisant autorité : [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md).

## État des lieux

### ✅ Portable tel quel

| Brique | Note |
|---|---|
| Riverpod / GoRouter / freezed / json_serializable | Aucune API plateforme |
| firebase_core / auth / firestore / functions / storage | SDK Flutter multi-plateformes (config à générer, voir chantiers) |
| Auth email+password & anonyme | `firebase_auth` portable tel quel |
| pdf (rendu quittances) + share_plus (partage) | Impls natives iOS/Android — share sheet natif **meilleur** que le web (⚠️ printing retiré : son `sharePdf` résout `true` dès l'ouverture du sheet, annulation indétectable) |
| shared_preferences (thème, format chart, view modes) | NSUserDefaults / SharedPreferences |
| fl_chart, flutter_svg, url_launcher, file_picker, intl, uuid, mime | OK mobile |
| Breakpoints UI (<600 = mobile) | Déjà pensés mobile-first sur les listes/cards |

### ✅ Web-only déjà isolé (stubs no-op hors web)

- `web_share_service_bridge.dart` — Web Share API (quittances) :
  `if (dart.library.js_interop)` → stub sur VM/mobile.
- `install_prompt_js_bridge_interface.dart` — prompt d'installation PWA :
  sans objet sur mobile, stub no-op.
- `package:web` n'apparaît **que** derrière ces bridges. Aucun `dart:html`.
- `kIsWeb` : seulement `firebase_options.dart` (généré) et
  `transitions.dart`.

### 🔧 Chantiers identifiés

1. **Auth sociale — LE chantier code** ([auth_repository.dart](../lib/features/auth/data/auth_repository.dart)) :
   `signInWithPopup` (web-only) utilisé ×4 — Google signup + link-anonyme,
   Apple signup + link-anonyme. Sur mobile : `signInWithProvider(provider)`
   (flux natif de `firebase_auth`, aucun package supplémentaire) — brancher
   par `kIsWeb`. Les gates CGU/RGPD et la logique d'upgrade anonyme sont
   inchangées.
2. **`firebase_options.dart` web-only** : jette `UnsupportedError` sur
   android/ios. Enregistrer les apps iOS + Android dans le projet Firebase
   (`easy-rent-54cd4`) puis rejouer `flutterfire configure` (génère aussi
   `google-services.json` / `GoogleService-Info.plist`).
3. **Dossiers de plateformes absents** : projet créé web-only →
   `flutter create . --platforms=android,ios --org <org>` (⚠️ décision
   bundle ID **avant**, définitive côté stores).
4. **Google Sign-In mobile** : empreintes SHA-1/SHA-256 (Android) à déclarer
   dans Firebase ; URL scheme inversé (iOS).
5. **Apple Sign-In** : capability Xcode + config Apple Developer. Rappel
   règle App Store : si un login social tiers est proposé sur iOS, Sign in
   with Apple est obligatoire.
6. **Partage quittances mobile** : le stub Web Share ne fait rien →
   brancher `share_plus` (choisi contre `printing.sharePdf`, qui ne
   remonte pas l'annulation du share sheet) dans le flux
   receipts quand `!kIsWeb`.
7. **Passe UI mobile native** : SafeArea (notch), comportement clavier
   (resizeToAvoidBottomInset), scroll physics, tailles de touch targets.
   Le splash `index.html` et la CSP sont sans objet sur mobile.
   **Réduite par FEAT-026** : le shell adaptatif fournit déjà la navigation
   tactile (NavigationBar) ; il reste surtout à valider SafeArea + clavier +
   touch targets. La `NavigationBar` doit vivre au-dessus du home indicator iOS
   / gesture bar Android (SafeArea bottom), le `NavigationRail` dans la SafeArea
   left en paysage.
9. **Shell de navigation adaptatif — FEAT-026 (prérequis nav)** : remplacer le
   hub-dashboard par `StatefulShellRoute.indexedStack` (5 branches : Accueil,
   Biens, Locataires, Baux, Profil) + `NavigationBar`/`NavigationRail`. Garde 3
   états conservée telle quelle. **À livrer sur le web avant / en J1** pour que
   la semaine mobile parte d'une base déjà navigable au tactile. Concept :
   [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md).
8. **Hors scope V1 mobile** (à backloger) : notifications push, deep/app
   links vérifiés (assetlinks.json / apple-app-site-association), App
   Check, offline avancé.

## Décisions à prendre (lundi, avant de coder)

| # | Décision | Options / défaut proposé | Impact |
|---|---|---|---|
| 1 | Bundle ID / applicationId | ex. `app.baillan.mobile` — définitif | `flutter create`, apps Firebase, stores |
| 2 | Cibles V1 | iOS + Android d'emblée, ou Android d'abord | compte Apple Developer (99 $/an) requis pour iOS |
| 3 | Distribution de test | TestFlight / Play interne / Firebase App Distribution | pipeline CI |
| 4 | Logins sociaux en V1 mobile | garder Google+Apple, ou email-only V1 | chantier n°1 réduit si email-only |
| 5 | minSdk / iOS minimum | défauts Flutter (Android 21+, iOS 12+) | rien de bloquant identifié |
| 6 | Shell nav FEAT-026 avant mobile | **oui, recommandé** (livrer web d'abord) vs faire en J1 | conditionne l'effort de la passe UI mobile (n°7) — voir décisions §13 de [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md) |

## Plan de semaine proposé

> **Idéal** : FEAT-026 (shell adaptatif) est mergé **sur le web avant J1**. Si ce
> n'est pas le cas, il devient le premier objectif de J1 — c'est un prérequis de
> navigation, pas un « nice-to-have » : on ne veut pas dupliquer une nav tactile
> par-dessus le hub-dashboard puis la jeter.

| Jour | Objectif |
|---|---|
| J1 | **Shell adaptatif FEAT-026** si non déjà mergé (`StatefulShellRoute.indexedStack` + NavigationBar/Rail, cf. [`docs/UX_NAVIGATION.md`](UX_NAVIGATION.md)) — sinon décisions ↑ directement. Puis `flutter create --platforms` + `flutterfire configure` + smoke run simulateur/émulateur |
| J2 | Branchement auth `kIsWeb` (`signInWithProvider`) + QA login email/Google/Apple sur devices |
| J3 | Passe UI mobile **allégée par le shell** (SafeArea sous NavigationBar, clavier, touch targets) + partage quittance natif (`share_plus`) |
| J4 | QA parcours métier complet iOS + Android (biens → locataires → baux → paiements → quittances), y compris navigation par onglets + préservation d'état ; corrections |
| J5 | CI builds (android/ios), distribution interne, doc + state refresh |

## Ce qui ne change pas

- **Firestore rules, indexes, Cloud Functions, modèle de données** :
  strictement identiques (même projet, mêmes contrats).
- **Le web continue de vivre** : une seule base de code, plusieurs cibles.
  Les gardes-fous (Firestore Rules, CGU/RGPD, quittances loi 1989) s'appliquent partout.
- **Versioning** : dérivé de git (tags + nb de commits), pas de `pubspec.yaml`
  — voir [`docs/VERSIONING.md`](VERSIONING.md). `--build-name` alimente
  versionName / CFBundleShortVersionString et `--build-number` alimente
  versionCode / CFBundleVersion, exactement comme le `version.json` du web
  (Profil → À propos affiche la même chose partout). Build mobile signé :

  ```bash
  flutter build appbundle --release \
    --dart-define=APP_ENV=prod \
    --build-name="$(bash tool/release/version.sh name)" \
    --build-number="$(bash tool/release/version.sh code)"
  ```

  > ⚠️ **`--dart-define=APP_ENV=prod` obligatoire sur les builds de release
  > mobile.** Sans lui, `APP_ENV` retombe sur son défaut `'dev'` → l'app afficherait
  > le badge « DEV/STAGING » à de vrais utilisateurs. La base Firestore, elle,
  > reste protégée quoi qu'il arrive : le `firestoreProvider` route **tout build
  > mobile de release** vers `(default)` (garde `kIsWeb` ; `MOBILE_STAGING` est
  > ignoré en release — ADR 0003) — mais l'affichage `Env.isProd` dépend bien de
  > ce flag. Seul le build **debug** de test avec `MOBILE_STAGING` vise `staging`
  > (cf. [Test Lab (Robo)](#test-lab-robo)).

  Le build number (= nb de commits) est strictement croissant → un nouveau
  build à uploader sur le store aura toujours un numéro supérieur au précédent
  (fini le rejet « versionCode already used »).

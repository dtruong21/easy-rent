# FEAT-024 — App mobile iOS/Android (préparation)

> Audit réalisé le 2026-07-03 (commit b699cb0) pour préparer le développement
> de la version mobile la semaine du 6 juillet 2026. Le codebase Flutter
> actuel (web) vise iOS et Android **sans réécriture** — même code, mêmes
> rules Firestore, mêmes Cloud Functions.

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
| pdf + printing (quittances) | Impls natives iOS/Android — `Printing.sharePdf` donne même un partage natif **meilleur** que le web |
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
   brancher `Printing.sharePdf` (dépendance déjà présente) dans le flux
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
| J3 | Passe UI mobile **allégée par le shell** (SafeArea sous NavigationBar, clavier, touch targets) + partage quittance natif (`Printing.sharePdf`) |
| J4 | QA parcours métier complet iOS + Android (biens → locataires → baux → paiements → quittances), y compris navigation par onglets + préservation d'état ; corrections |
| J5 | CI builds (android/ios), distribution interne, doc + state refresh |

## Ce qui ne change pas

- **Firestore rules, indexes, Cloud Functions, modèle de données** :
  strictement identiques (même projet, mêmes contrats).
- **Le web continue de vivre** : une seule base de code, plusieurs cibles.
  Les gardes-fous (RLS, CGU/RGPD, quittances loi 1989) s'appliquent partout.
- **Versioning** : `pubspec.yaml` porte la version unique ; sur mobile,
  `--build-number` alimentera versionCode / CFBundleVersion comme il
  alimente `version.json` sur le web (Profil → À propos affichera la même
  chose).

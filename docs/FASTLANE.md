# Livraison mobile — Fastlane + perf de build

> Mis en place pour la livraison store **ultérieure**. Android = exécutable dès
> qu'un JSON de compte de service Play est fourni. iOS = **scaffold seul**,
> bloqué tant que le compte Apple Developer (payant) n'existe pas.
> Versioning **dérivé de git** : passer `build_name`/`build_number` aux lanes,
> **ne jamais bumper `pubspec`** (cf. [`docs/VERSIONING.md`]).

## 1. Accélérations de build appliquées

| Zone | Fichier | Changement | Effet |
|---|---|---|---|
| Android | `android/gradle.properties` | `org.gradle.caching`, `org.gradle.parallel`, `kotlin.incremental` + JVM 8G→6G / metaspace 4G→2G + `UseParallelGC` | Réutilise les sorties de tâches entre builds/worktrees, compile les plugins Firebase en parallèle, libère de la RAM. Gains « à froid » et « à chaud ». |
| iOS | `ios/Podfile` | Firestore/gRPC/BoringSSL/abseil **précompilés** (xcframeworks invertase, tag `11.15.0`) au lieu d'une compile C++ depuis les sources | Poste le plus lourd du build iOS à froid — réduction ~60-70 % documentée. |
| iOS | `ios/Podfile` | `COMPILER_INDEX_STORE_ENABLE=NO` sur les pods | Supprime l'index-store (IDE-only) pour les builds CLI. |

**⚠️ Couplage de version iOS** : le `:tag` du pod `FirebaseFirestore` DOIT rester
égal à la version `FirebaseFirestore` résolue dans `ios/Podfile.lock`. Quand
`cloud_firestore` est bumpé (→ nouvelle version Firestore), **remonter le tag en
même temps** dans le `Podfile`, sinon `pod install` échoue. Retirer la ligne
revient au comportement « compile depuis les sources ».

**Écartés volontairement** (peuvent casser le build) : Gradle
`configuration-cache` (plugin Flutter pas compatible — flutter#155484),
`configureondemand`, `isMinifyEnabled/isShrinkResources` pour la vitesse (c'est
un levier de *taille*, il *ralentit* le build). Ne pas activer sans mesure.

### Mesurer

- Android : `cd android && ./gradlew :app:bundleRelease --profile` → rapport dans
  `android/app/build/reports/profile/`. Vérifier `FROM-CACHE` avec `--build-cache -i`.
  Comparer à froid (`rm -rf ~/.gradle/caches`) et à chaud.
- iOS : chronométrer un build **à froid** (`rm -rf ios/Pods ios/Podfile.lock`)
  avec vs sans le pod précompilé.
- Codegen : `time dart run build_runner build --delete-conflicting-outputs`
  (à froid vs à chaud). NB : `flutter run`/`build` ne relancent PAS build_runner ;
  le coût n'est payé qu'en worktree neuf ou après édition d'un modèle annoté.

## 2. Prérequis Fastlane (une fois)

1. **Ruby 3.3** (le Ruby système 2.6 est trop vieux pour `supply`). Via rbenv/Homebrew.
   `.ruby-version` (3.3.5) est déjà posé dans `android/` et `ios/`.
2. `cd android && bundle install` puis `cd ios && bundle install` (génère les `Gemfile.lock` — à committer).
3. Tout se lance en `bundle exec fastlane <lane>` **depuis `android/` ou `ios/`**.

## 3. Android — livraison Play (exécutable maintenant)

Prérequis restant : un **JSON de compte de service Play** (Play Console → Setup →
API access), rôle « Release apps to testing tracks ». Le déposer en
`android/play-store-service-account.json` (gitignored) ou via `SUPPLY_JSON_KEY`.
Le keystore upload + `android/key.properties` existent déjà (signent l'AAB).
⚠️ Au moins **un AAB doit avoir été uploadé manuellement une première fois** dans
la console (l'API Play refuse le tout premier upload) — déjà fait (#82).

Lanes (`android/fastlane/Fastfile`) :
- `build` — AAB release signé (`flutter build appbundle --release`).
- `beta` — build + upload piste **internal** en **brouillon** (`release_status: draft`).
- `deploy` — build + upload piste **beta** en brouillon.

```bash
cd android
bundle exec fastlane beta build_name:1.2.3 build_number:456
# → un brouillon apparaît sur la piste internal ; un humain clique
#   « examiner & déployer » (rien ne part en prod automatiquement).
```

## 4. iOS — TestFlight/App Store (scaffold, bloqué)

**Bloqué** tant que le **compte Apple Developer (99 $/an)** n'est pas actif.
Credentials à fournir alors (tous en `.env`/CI, **jamais commités**) :
- App Store Connect **API key** : `.p8` (dans `ios/private_keys/`) + `ASC_KEY_ID` + `ASC_ISSUER_ID`.
- **match** : `MATCH_GIT_URL` (dépôt privé de certs chiffrés) + `MATCH_PASSWORD`.
- Team IDs : `APPLE_DEV_TEAM_ID`, `ASC_TEAM_ID`, `FASTLANE_APPLE_ID`.
- App ID `com.daki.baillan` enregistré au Developer Portal + fiche créée dans ASC.
- Copier `ios/ExportOptions.plist.example` → `ios/ExportOptions.plist` (gitignored) et renseigner `teamID`.

Lanes (`ios/fastlane/Fastfile`) : `build` (IPA) · `beta` (match + `flutter build ipa` + upload TestFlight).

## 5. Sécurité — ne jamais committer

`play-store-service-account.json`, `*.p8`, `private_keys/`, `key.properties`,
`*.jks`, `MATCH_PASSWORD`, `ExportOptions.plist`, `.env*`. Déjà couverts par
`android/.gitignore` / `ios/.gitignore` / `.gitignore` racine — vérifier
`git status` avant tout commit fastlane.

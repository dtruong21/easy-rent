import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Infos de build de l'app (version sémantique + numéro de build).
///
/// La version est DÉRIVÉE de git au build (voir `tool/release/version.sh` et
/// `docs/VERSIONING.md`), pas éditée dans pubspec.yaml :
///   - version (X.Y.Z) = dernier tag `vX.Y.Z`  (`--build-name`)
///   - build number    = `git rev-list --count HEAD` (`--build-number`),
///     strictement croissant → contrainte des stores satisfaite.
/// - Web : `PackageInfo` lit `version.json` émis par `flutter build web`
///   (servi no-cache, voir firebase.json).
/// - iOS/Android (FEAT-024) : mêmes valeurs injectées dans
///   versionName/versionCode (CFBundleShortVersionString/CFBundleVersion),
///   lues par le même appel [PackageInfo.fromPlatform].
///
/// Affiché dans Profil → À propos. Le codename (essence d'arbre) de la release
/// vit dans le tag / la GitHub Release, pas dans l'app.
final appInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

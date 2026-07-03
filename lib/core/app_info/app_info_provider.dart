import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Infos de build de l'app (version sémantique + numéro de build).
///
/// - Web : lit `version.json` émis par `flutter build web` (servi no-cache,
///   voir firebase.json) — version depuis pubspec.yaml, build number injecté
///   par `--build-number` au build (CI : run GitHub ; local : nb de commits).
/// - iOS/Android (FEAT-024) : lira Info.plist / build.gradle via le même
///   appel [PackageInfo.fromPlatform].
///
/// Affiché dans Profil → À propos.
final appInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Enveloppe Firebase Crashlytics — **mobile uniquement** (iOS / Android).
///
/// Crashlytics n'a PAS d'implémentation web : chaque appel est gardé par
/// [kIsWeb] et devient un no-op sur le web (le PWA n'a pas de rapport
/// d'incident — décision produit 2026-07-09, web-first).
///
/// RGPD : la collecte est **désactivée par défaut** (opt-in). Les hooks
/// d'erreur sont branchés dès [initialize], mais Crashlytics n'émet rien tant
/// que [setEnabled] n'a pas reçu `true` — ce que fait `CrashReportingNotifier`
/// uniquement après consentement explicite de l'utilisateur.
class CrashReportingService {
  const CrashReportingService._();

  /// Branche les erreurs Flutter (framework, synchrones) et les erreurs
  /// asynchrones de la plateforme vers Crashlytics. No-op sur le web.
  ///
  /// À appeler une seule fois, après `Firebase.initializeApp` et avant
  /// `runApp`. Les deux hooks remplacent le besoin d'un `runZonedGuarded`.
  static void initialize() {
    if (kIsWeb) return;
    final crashlytics = FirebaseCrashlytics.instance;

    // Erreurs synchrones du framework Flutter.
    FlutterError.onError = crashlytics.recordFlutterFatalError;

    // Erreurs asynchrones non capturées.
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Active/désactive la collecte Crashlytics (le SDK persiste ce choix).
  /// No-op sur le web. Piloté par le consentement utilisateur.
  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }
}

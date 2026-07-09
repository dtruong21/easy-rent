/// Tests — persistance du consentement au rapport d'incident (Crashlytics).
///
/// Invariant RGPD clé : **opt-in**. Sans valeur stockée, `read()` renvoie
/// `null` → traité comme refus (collecte désactivée par défaut dans `main()`).
library;

import 'package:easyrent/core/observability/crash_reporting_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrashReportingStorage — opt-in RGPD', () {
    test('read() → null quand rien n\'est stocké (défaut = refus)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CrashReportingStorage().read(), isNull);
    });

    test('write(true) puis read() → true', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = CrashReportingStorage();
      await storage.write(true);
      expect(await storage.read(), isTrue);
    });

    test('write(false) puis read() → false', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = CrashReportingStorage();
      await storage.write(false);
      expect(await storage.read(), isFalse);
    });
  });
}

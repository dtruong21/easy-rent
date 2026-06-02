/// Tests unitaires pour [InstallPromptStorage].
library;

import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    final storage = InstallPromptStorage();
    await storage.clear();
  });

  group('saveDismissedAt + isDismissedRecently', () {
    test('dismiss récent → isDismissedRecently = true', () async {
      final storage = InstallPromptStorage();
      await storage.saveDismissedAt(DateTime.now());
      final recent = await storage.isDismissedRecently();
      expect(recent, isTrue);
    });

    test('pas de dismiss → isDismissedRecently = false', () async {
      final storage = InstallPromptStorage();
      final recent = await storage.isDismissedRecently();
      expect(recent, isFalse);
    });

    test('dismiss il y a >30 jours → isDismissedRecently = false', () async {
      final storage = InstallPromptStorage();
      // Simule un dismiss il y a 31 jours.
      final oldDate = DateTime.now().subtract(const Duration(days: 31));
      await storage.saveDismissedAt(oldDate);
      final recent = await storage.isDismissedRecently();
      expect(recent, isFalse);
    });
  });

  group('markFirstLoginSeen + isFirstLoginSeen', () {
    test('pas encore vu → isFirstLoginSeen = false', () async {
      final storage = InstallPromptStorage();
      final seen = await storage.isFirstLoginSeen();
      expect(seen, isFalse);
    });

    test('après markFirstLoginSeen → isFirstLoginSeen = true', () async {
      final storage = InstallPromptStorage();
      await storage.markFirstLoginSeen();
      final seen = await storage.isFirstLoginSeen();
      expect(seen, isTrue);
    });
  });

  group('clear', () {
    test('clear remet les valeurs à zéro', () async {
      final storage = InstallPromptStorage();
      await storage.saveDismissedAt(DateTime.now());
      await storage.markFirstLoginSeen();
      await storage.clear();
      expect(await storage.isDismissedRecently(), isFalse);
      expect(await storage.isFirstLoginSeen(), isFalse);
    });
  });
}

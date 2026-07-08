/// Tests de [LocaleNotifier] + [LocaleStorage] (FEAT-043 — i18n).
///
/// Couvre :
/// - Défaut `null` (= système) quand rien n'est persisté
/// - Chargement de la préférence persistée au démarrage
/// - Valeur inconnue persistée → retombe sur `null` (système)
/// - setLocale change l'état et persiste (y compris réinitialisation à
///   `null`)
///
/// Calque exact de `test/core/theme/theme_mode_provider_test.dart`
/// (FEAT-023).
library;

import 'package:easyrent/core/i18n/locale_provider.dart';
import 'package:easyrent/core/i18n/locale_storage.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocaleNotifier', () {
    test('défaut — null (système) quand rien n\'est persisté', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);
      // Laisse le chargement async se terminer — reste null.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localeProvider), isNull);
    });

    test('charge la préférence persistée au démarrage (en)', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(localeProvider); // instancie le notifier
      await Future<void>.delayed(Duration.zero);

      expect(container.read(localeProvider), const Locale('en'));
    });

    test('charge la préférence persistée au démarrage (fr)', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'fr'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(localeProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(localeProvider), const Locale('fr'));
    });

    test('valeur inconnue persistée → retombe sur null (système)', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'de'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(localeProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(localeProvider), isNull);
    });

    test('setLocale change l\'état et persiste', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('en'));

      expect(container.read(localeProvider), const Locale('en'));
      final persisted = await LocaleStorage().read();
      expect(persisted, 'en');
    });

    test(
      'setLocale(null) réinitialise sur système et efface la persistance',
      (() async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(localeProvider.notifier)
            .setLocale(const Locale('en'));
        await container.read(localeProvider.notifier).setLocale(null);

        expect(container.read(localeProvider), isNull);
        final persisted = await LocaleStorage().read();
        expect(persisted, isNull);
      }),
    );
  });

  group('LocaleStorage', () {
    test('read sans écriture préalable → null', () async {
      final result = await LocaleStorage().read();
      expect(result, isNull);
    });

    test('write + read → même valeur', () async {
      final storage = LocaleStorage();
      await storage.write('en');
      final result = await storage.read();
      expect(result, 'en');
    });

    test('write(null) efface la préférence', () async {
      final storage = LocaleStorage();
      await storage.write('fr');
      await storage.write(null);
      final result = await storage.read();
      expect(result, isNull);
    });

    test('valeur inconnue en storage → read retourne null', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'de'});
      final result = await LocaleStorage().read();
      expect(result, isNull);
    });
  });
}

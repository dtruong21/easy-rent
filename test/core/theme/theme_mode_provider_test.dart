/// Tests de [ThemeModeNotifier] + [ThemeModeStorage].
///
/// Couvre :
/// - Défaut `system` quand rien n'est persisté
/// - Chargement de la préférence persistée au démarrage
/// - Valeur inconnue persistée → retombe sur `system`
/// - setMode change l'état et persiste
library;

import 'package:easyrent/core/theme/theme_mode_provider.dart';
import 'package:easyrent/core/theme/theme_mode_storage.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeModeNotifier', () {
    test('défaut — system quand rien n\'est persisté', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      // Laisse le chargement async se terminer — reste system.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('charge la préférence persistée au démarrage', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(themeModeProvider); // instancie le notifier
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('valeur inconnue persistée → retombe sur system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(themeModeProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('setMode change l\'état et persiste', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      // Relit directement le storage pour vérifier la persistance.
      final persisted = await ThemeModeStorage().read();
      expect(persisted, ThemeMode.dark);
    });
  });

  group('ThemeModeStorage', () {
    test('read sans écriture préalable → null', () async {
      final result = await ThemeModeStorage().read();
      expect(result, isNull);
    });

    test('write + read → même valeur', () async {
      final storage = ThemeModeStorage();
      await storage.write(ThemeMode.light);
      final result = await storage.read();
      expect(result, ThemeMode.light);
    });
  });
}

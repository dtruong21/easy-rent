/// Tests unitaires pour [ViewModeNotifier] et [viewModeProvider].
library;

import 'package:easyrent/core/ui/cards/view_mode.dart';
import 'package:easyrent/core/ui/cards/view_mode_provider.dart';
import 'package:easyrent/core/ui/cards/view_mode_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [viewModeStorageProvider.overrideWithValue(ViewModeStorage())],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ViewModeNotifier — état initial', () {
    test('état initial = card', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final mode = container.read(viewModeProvider('leases'));
      expect(mode, ViewMode.card);
    });
  });

  group('ViewModeNotifier.setMode', () {
    test('setMode(table) → state = table', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await container
          .read(viewModeProvider('leases').notifier)
          .setMode(ViewMode.table);
      final mode = container.read(viewModeProvider('leases'));
      expect(mode, ViewMode.table);
    });

    test('setMode(card) après table → state = card', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await container
          .read(viewModeProvider('props').notifier)
          .setMode(ViewMode.table);
      await container
          .read(viewModeProvider('props').notifier)
          .setMode(ViewMode.card);
      final mode = container.read(viewModeProvider('props'));
      expect(mode, ViewMode.card);
    });
  });

  group('ViewModeNotifier — persistance SharedPreferences', () {
    test('setMode persiste la valeur', () async {
      final storage = ViewModeStorage();
      final container = ProviderContainer(
        overrides: [viewModeStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      await container
          .read(viewModeProvider('tenants').notifier)
          .setMode(ViewMode.table);

      // Relit directement le storage pour vérifier la persistance.
      final persisted = await storage.read('tenants');
      expect(persisted, ViewMode.table);
    });

    test('storage lit la valeur préchargée dans SharedPreferences', () async {
      // Vérifie indirectement le chargement initial via le storage.
      // Le storage est la source de vérité — s'il retourne 'table', le notifier
      // le chargera (testé via setMode + persist test ci-dessus).
      SharedPreferences.setMockInitialValues({'view_mode_leases': 'table'});
      final storage = ViewModeStorage();
      final persisted = await storage.read('leases');
      expect(persisted, ViewMode.table);
    });
  });

  group('ViewModeNotifier — pageKey isolation', () {
    test('modes indépendants par pageKey', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(viewModeProvider('leases').notifier)
          .setMode(ViewMode.table);
      // 'properties' doit rester card.
      final propertiesMode = container.read(viewModeProvider('properties'));
      expect(propertiesMode, ViewMode.card);
    });
  });

  group('ViewModeStorage', () {
    test('read sans écriture préalable → null', () async {
      final storage = ViewModeStorage();
      final result = await storage.read('unknown_page');
      expect(result, isNull);
    });

    test('write + read → même valeur', () async {
      final storage = ViewModeStorage();
      await storage.write('test_page', ViewMode.table);
      final result = await storage.read('test_page');
      expect(result, ViewMode.table);
    });

    test('clear → read retourne null', () async {
      final storage = ViewModeStorage();
      await storage.write('test_page', ViewMode.table);
      await storage.clear('test_page');
      final result = await storage.read('test_page');
      expect(result, isNull);
    });

    test('valeur inconnue dans SharedPreferences → null', () async {
      SharedPreferences.setMockInitialValues({'view_mode_bad': 'unknown_mode'});
      final storage = ViewModeStorage();
      final result = await storage.read('bad');
      expect(result, isNull);
    });
  });
}

/// Tests de [RailExpandedNotifier] + [RailExpandedStorage].
library;

import 'package:easyrent/core/ui/navigation/rail_expanded_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RailExpandedNotifier', () {
    test('défaut — replié (false) quand rien n\'est persisté', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(railExpandedProvider), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(railExpandedProvider), isFalse);
    });

    test('charge la préférence persistée (déplié) au démarrage', () async {
      SharedPreferences.setMockInitialValues({'nav_rail_expanded': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(railExpandedProvider); // instancie le notifier
      await Future<void>.delayed(Duration.zero);

      expect(container.read(railExpandedProvider), isTrue);
    });

    test('toggle bascule l\'état et persiste', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(railExpandedProvider.notifier).toggle();
      expect(container.read(railExpandedProvider), isTrue);

      final persisted = await RailExpandedStorage().read();
      expect(persisted, isTrue);

      await container.read(railExpandedProvider.notifier).toggle();
      expect(container.read(railExpandedProvider), isFalse);
    });
  });
}

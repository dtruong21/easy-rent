/// Tests de [ChartPeriodNotifier] + [ChartPeriodStorage].
///
/// Couvre :
/// - Défaut `m6` quand rien n'est persisté
/// - Chargement de la préférence persistée au démarrage
/// - Valeur inconnue persistée → retombe sur `m6`
/// - setPeriod change l'état et persiste
library;

import 'package:easyrent/features/dashboard/application/chart_period_provider.dart';
import 'package:easyrent/features/dashboard/domain/chart_period.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChartPeriodNotifier', () {
    test('défaut — m6 quand rien n\'est persisté', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(chartPeriodProvider), ChartPeriod.m6);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(chartPeriodProvider), ChartPeriod.m6);
    });

    test('charge la préférence persistée au démarrage', () async {
      SharedPreferences.setMockInitialValues({'chart_period_monthly': 'm24'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chartPeriodProvider); // instancie le notifier
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chartPeriodProvider), ChartPeriod.m24);
    });

    test('valeur inconnue persistée → retombe sur m6', () async {
      SharedPreferences.setMockInitialValues({'chart_period_monthly': 'm36'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chartPeriodProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chartPeriodProvider), ChartPeriod.m6);
    });

    test('setPeriod change l\'état et persiste', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(chartPeriodProvider.notifier)
          .setPeriod(ChartPeriod.m12);

      expect(container.read(chartPeriodProvider), ChartPeriod.m12);
      final persisted = await ChartPeriodStorage().read();
      expect(persisted, ChartPeriod.m12);
    });
  });
}

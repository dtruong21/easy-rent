/// Tests de [ChartFormatNotifier] + [ChartFormatStorage].
///
/// Couvre :
/// - Défaut `bars` quand rien n'est persisté
/// - Chargement de la préférence persistée au démarrage
/// - Valeur inconnue persistée → retombe sur `bars`
/// - setFormat change l'état et persiste
library;

import 'package:easyrent/features/dashboard/application/chart_format_provider.dart';
import 'package:easyrent/features/dashboard/domain/chart_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChartFormatNotifier', () {
    test('défaut — bars quand rien n\'est persisté', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(chartFormatProvider), ChartFormat.bars);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(chartFormatProvider), ChartFormat.bars);
    });

    test('charge la préférence persistée au démarrage', () async {
      SharedPreferences.setMockInitialValues({'chart_format_monthly': 'area'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chartFormatProvider); // instancie le notifier
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chartFormatProvider), ChartFormat.area);
    });

    test('valeur inconnue persistée → retombe sur bars', () async {
      SharedPreferences.setMockInitialValues({
        'chart_format_monthly': 'camembert',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chartFormatProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chartFormatProvider), ChartFormat.bars);
    });

    test('setFormat change l\'état et persiste', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(chartFormatProvider.notifier)
          .setFormat(ChartFormat.line);

      expect(container.read(chartFormatProvider), ChartFormat.line);
      final persisted = await ChartFormatStorage().read();
      expect(persisted, ChartFormat.line);
    });
  });
}

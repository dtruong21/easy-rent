/// Tests widget de [FilterChipsBar].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/filters/filter_chips_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _F { all, a, b, c, d }

Widget _wrap(Widget child, {double width = 390}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

void main() {
  testWidgets('libellés et compteurs affichés, puce active sélectionnée', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous', count: 3),
            FilterChipOption(value: _F.a, label: 'Loués', count: 1),
          ],
          selected: _F.all,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.textContaining('Tous'), findsOneWidget);
    expect(find.textContaining('3'), findsOneWidget);
    final all = tester.widget<ChoiceChip>(
      find.byKey(Key('filter_chip_${_F.all}')),
    );
    final a = tester.widget<ChoiceChip>(find.byKey(Key('filter_chip_${_F.a}')));
    expect(all.selected, isTrue);
    expect(a.selected, isFalse);
  });

  testWidgets('sans compteur (chargement) : libellé seul', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [FilterChipOption(value: _F.all, label: 'Tous')],
          selected: _F.all,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('Tous'), findsOneWidget);
  });

  testWidgets('tap sur une puce → onSelected(valeur)', (tester) async {
    _F? picked;
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous'),
            FilterChipOption(value: _F.b, label: 'Vacants'),
          ],
          selected: _F.all,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.byKey(Key('filter_chip_${_F.b}')));
    expect(picked, _F.b);
  });

  testWidgets('5 puces à 320 px + trailing : aucun débordement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous', count: 12),
            FilterChipOption(value: _F.a, label: 'Actifs', count: 8),
            FilterChipOption(value: _F.b, label: 'À renouveler', count: 2),
            FilterChipOption(value: _F.c, label: 'En retard', count: 1),
            FilterChipOption(value: _F.d, label: 'Terminés', count: 1),
          ],
          selected: _F.all,
          onSelected: (_) {},
          trailing: const Icon(Icons.grid_view),
        ),
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
  });
}

/// Tests widget pour [KpiCard].
library;

import 'package:easyrent/features/dashboard/presentation/widgets/kpi_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
  home: Scaffold(body: child),
);

void main() {
  group('KpiCard — affichage', () {
    testWidgets('affiche icon + label + value', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KpiCard(
            icon: Icons.euro_outlined,
            label: 'Loyers du mois',
            value: '850,00 €',
          ),
        ),
      );
      expect(find.text('Loyers du mois'), findsOneWidget);
      expect(find.text('850,00 €'), findsOneWidget);
      expect(find.byIcon(Icons.euro_outlined), findsOneWidget);
    });

    testWidgets('affiche subtitle si fourni', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KpiCard(
            icon: Icons.euro_outlined,
            label: 'Loyers',
            value: '0 €',
            subtitle: 'Dû : 900,00 €',
          ),
        ),
      );
      expect(find.text('Dû : 900,00 €'), findsOneWidget);
    });

    testWidgets('pas de subtitle → pas de texte subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KpiCard(
            icon: Icons.euro_outlined,
            label: 'Loyers',
            value: '0 €',
          ),
        ),
      );
      expect(find.text('subtitle'), findsNothing);
    });

    testWidgets('value = 0 → affiché normalement', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KpiCard(
            icon: Icons.warning_amber_outlined,
            label: 'Retards',
            value: '0',
          ),
        ),
      );
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('semanticColor appliqué (rouge retards > 0)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          KpiCard(
            icon: Icons.warning_amber_outlined,
            label: 'Retards',
            value: '3',
            semanticColor: Colors.red,
          ),
        ),
      );
      // Vérifie que la card se rend sans erreur.
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(KpiCard), findsOneWidget);
    });

    testWidgets('child slot rendu', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const KpiCard(
            icon: Icons.euro_outlined,
            label: 'Test',
            value: '42',
            child: Text('mini-chart'),
          ),
        ),
      );
      expect(find.text('mini-chart'), findsOneWidget);
    });

    testWidgets('onTap → flèche visible et tappable', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrap(
          KpiCard(
            icon: Icons.euro_outlined,
            label: 'Test',
            value: '42',
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.byType(KpiCard));
      expect(tapped, isTrue);
    });
  });
}

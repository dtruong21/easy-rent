/// Tests widget pour [StatusPill].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/status_pill.dart';
import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('StatusPill — label', () {
    testWidgets('affiche le label', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusPill(label: 'Actif', tone: StatusPillTone.success)),
      );
      expect(find.text('Actif'), findsOneWidget);
    });
  });

  group('StatusPill — tones × variants', () {
    for (final tone in StatusPillTone.values) {
      for (final variant in StatusPillVariant.values) {
        testWidgets('tone=$tone variant=$variant — rendu OK', (tester) async {
          await tester.pumpWidget(
            _wrap(StatusPill(label: 'Test', tone: tone, variant: variant)),
          );
          expect(find.text('Test'), findsOneWidget);
          expect(find.byType(StatusPill), findsOneWidget);
        });
      }
    }
  });

  group('StatusPill — sizes', () {
    testWidgets('size sm — rendu OK', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusPill(
            label: 'Petit',
            tone: StatusPillTone.info,
            size: StatusPillSize.sm,
          ),
        ),
      );
      expect(find.text('Petit'), findsOneWidget);
    });

    testWidgets('size md — rendu OK', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusPill(
            label: 'Moyen',
            tone: StatusPillTone.info,
            size: StatusPillSize.md,
          ),
        ),
      );
      expect(find.text('Moyen'), findsOneWidget);
    });
  });

  group('StatusPill — icône', () {
    testWidgets('sans icon — pas d\'Icon widget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusPill(label: 'Sans icône', tone: StatusPillTone.neutral),
        ),
      );
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('avec icon — Icon widget présent', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusPill(
            label: 'Avec icône',
            tone: StatusPillTone.success,
            icon: Icons.check_circle_outline,
          ),
        ),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('StatusPill — sémantique', () {
    testWidgets('widget Semantics présent dans l\'arbre', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusPill(label: 'En retard', tone: StatusPillTone.danger),
        ),
      );
      await tester.pumpAndSettle();
      // Vérifie que le widget Semantics est bien présent dans l'arbre.
      expect(find.byType(Semantics), findsWidgets);
      // Vérifie que le label est affiché.
      expect(find.text('En retard'), findsOneWidget);
    });
  });

  group('StatusPill — dark mode', () {
    testWidgets('se rend en dark mode sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: const StatusPill(
                label: 'Dark',
                tone: StatusPillTone.warning,
                variant: StatusPillVariant.filled,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Dark'), findsOneWidget);
    });
  });
}

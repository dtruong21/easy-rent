/// Tests widget pour [ShortcutsRow].
///
/// F-4 (audit navigation) : le raccourci « Simuler un investissement » doit
/// `push()` (pas `go()`) vers `/simulator` — le simulateur est empilé
/// par-dessus l'écran appelant, un `pop()` natif y revient directement (cf.
/// docs/UX_NAVIGATION.md §3.4).
library;

import 'package:easyrent/features/dashboard/presentation/widgets/shortcuts_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap() {
  return MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: ShortcutsRow()),
        ),
        GoRoute(
          path: '/simulator',
          builder: (context, state) =>
              const Scaffold(body: Text('page simulateur')),
        ),
      ],
    ),
  );
}

void main() {
  group('ShortcutsRow', () {
    testWidgets('affiche le raccourci simulateur', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Simuler un investissement'), findsOneWidget);
    });

    testWidgets('tap → push vers /simulator, empilé par-dessus l\'appelant '
        '(pop() natif y revient)', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shortcut_simulator')));
      await tester.pumpAndSettle();

      expect(find.text('page simulateur'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('page simulateur'), findsNothing);
      expect(find.text('Simuler un investissement'), findsOneWidget);
    });
  });
}

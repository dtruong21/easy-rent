import 'package:easyrent/core/ui/app_bar/app_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Construit l'app avec un Navigator à 2 niveaux pour simuler canPop == true.
Widget _buildAppWithPoppableStack({required AppAppBar appBar}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: const Text('root')),
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(appBar: appBar),
                ),
              ),
              child: const Text('push'),
            ),
          ),
        );
      },
    ),
  );
}

/// Construit l'app avec GoRouter pour tester la navigation fallback.
Widget _buildAppWithGoRouter({required String fallbackRoute}) {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(
        path: '/test',
        builder: (context, state) => Scaffold(
          appBar: AppAppBar(title: 'Test', fallbackRoute: fallbackRoute),
        ),
      ),
      GoRoute(
        path: fallbackRoute,
        builder: (context, state) => const Scaffold(body: Text('destination')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AppAppBar', () {
    // -------------------------------------------------------------------------
    // Cas 1 : canPop == true → BackButton Material
    // -------------------------------------------------------------------------
    testWidgets('canPop == true → affiche BackButton Material, click → pop', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildAppWithPoppableStack(
          appBar: const AppAppBar(title: 'Detail', fallbackRoute: '/other'),
        ),
      );

      // Ouvre la 2e page (canPop sera true dessus).
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      // Un BackButton doit être affiché (avec Key 'app_bar_back').
      expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
      // Doit être de type BackButton.
      expect(find.byType(BackButton), findsOneWidget);

      // Click → pop → retour à la page root.
      await tester.tap(find.byKey(const Key('app_bar_back')));
      await tester.pumpAndSettle();

      expect(find.text('root'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Cas 2 : canPop == false + fallbackRoute → IconButton avec Key
    // -------------------------------------------------------------------------
    testWidgets(
      'canPop == false ET fallbackRoute → IconButton Key app_bar_back, '
      'click → navigue vers fallbackRoute',
      (tester) async {
        await tester.pumpWidget(_buildAppWithGoRouter(fallbackRoute: '/'));
        await tester.pumpAndSettle();

        // Aucun pop possible (route racine GoRouter).
        // Doit afficher un IconButton (pas un BackButton).
        expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(find.byType(IconButton), findsOneWidget);

        // Click → navigue vers '/'.
        await tester.tap(find.byKey(const Key('app_bar_back')));
        await tester.pumpAndSettle();

        expect(find.text('destination'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // Cas 3 : canPop == false + fallbackRoute == null → pas de leading
    // -------------------------------------------------------------------------
    testWidgets('canPop == false ET fallbackRoute == null → leading null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: const AppAppBar(title: 'Sans retour')),
        ),
      );
      await tester.pumpAndSettle();

      // Pas de bouton retour.
      expect(find.byKey(const Key('app_bar_back')), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      // On vérifie aussi qu'aucun IconButton d'arrow_back n'est présent.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Cas 4 : showBackButton: false → leading null même si canPop
    // -------------------------------------------------------------------------
    testWidgets('showBackButton: false → pas de leading même avec canPop', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildAppWithPoppableStack(
          appBar: const AppAppBar(
            title: 'Dashboard',
            showBackButton: false,
            fallbackRoute: '/',
          ),
        ),
      );

      // Ouvre la 2e page (canPop == true).
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      // showBackButton: false → aucun leading.
      expect(find.byKey(const Key('app_bar_back')), findsNothing);
      expect(find.byType(BackButton), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Cas 5 : leading != null → override total
    // -------------------------------------------------------------------------
    testWidgets('leading != null → override total (ignore canPop)', (
      tester,
    ) async {
      const customLeadingKey = Key('custom_leading');

      await tester.pumpWidget(
        _buildAppWithPoppableStack(
          appBar: const AppAppBar(
            title: 'Custom',
            leading: Icon(Icons.menu, key: customLeadingKey),
          ),
        ),
      );

      // Ouvre la 2e page.
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      // Le leading custom est affiché.
      expect(find.byKey(customLeadingKey), findsOneWidget);
      // Pas de BackButton ni d'IconButton arrow_back.
      expect(find.byType(BackButton), findsNothing);
      expect(find.byKey(const Key('app_bar_back')), findsNothing);
    });
  });
}

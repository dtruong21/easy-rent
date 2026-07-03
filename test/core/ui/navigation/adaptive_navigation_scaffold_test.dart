/// Tests widget pour [AdaptiveNavigationScaffold] (FEAT-026).
///
/// Le shell est exercé via un [StatefulShellRoute.indexedStack] minimal à 5
/// branches factices (contenu trivial) — on teste le MÉCANISME du shell
/// (NavigationBar/Rail selon largeur, goBranch, préservation d'état), pas les
/// pages métier réelles (couvertes par leurs propres tests + par
/// `shell_branch_state_test.dart` pour l'intégration avec le vrai routeur).
library;

import 'package:easyrent/core/ui/navigation/adaptive_navigation_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Router de test — 5 branches factices avec un champ de saisie chacune, pour
// pouvoir prouver la préservation d'état par indexedStack (un TextField
// gardant sa valeur après changement d'onglet ne serait pas possible avec un
// ShellRoute simple qui reconstruit le widget à chaque bascule).
// ---------------------------------------------------------------------------

Widget _brancheFactice(String label) => Scaffold(
  body: Center(
    child: TextField(
      key: Key('field_$label'),
      decoration: InputDecoration(labelText: label),
    ),
  ),
);

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/accueil',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveNavigationScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accueil',
                builder: (context, state) => _brancheFactice('accueil'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/biens',
                builder: (context, state) => _brancheFactice('biens'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/locataires',
                builder: (context, state) => _brancheFactice('locataires'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/baux',
                builder: (context, state) => _brancheFactice('baux'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profil',
                builder: (context, state) => _brancheFactice('profil'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _setViewportWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group(
    'AdaptiveNavigationScaffold — bascule NavigationBar / NavigationRail',
    () {
      testWidgets('< 600 px → NavigationBar présente, NavigationRail absente', (
        tester,
      ) async {
        await _setViewportWidth(tester, 400);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('adaptive_nav_bar')), findsOneWidget);
        expect(find.byKey(const Key('adaptive_nav_rail')), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      });

      testWidgets(
        '>= 600 px → NavigationRail présente, NavigationBar absente',
        (tester) async {
          await _setViewportWidth(tester, 900);
          await tester.pumpWidget(
            MaterialApp.router(routerConfig: _buildTestRouter()),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('adaptive_nav_rail')), findsOneWidget);
          expect(find.byKey(const Key('adaptive_nav_bar')), findsNothing);
          expect(find.byType(NavigationRail), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
        },
      );

      testWidgets('exactement 600 px (breakpoint) → bascule côté large (>=)', (
        tester,
      ) async {
        await _setViewportWidth(tester, 600);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('adaptive_nav_rail')), findsOneWidget);
        expect(find.byKey(const Key('adaptive_nav_bar')), findsNothing);
      });
    },
  );

  group('AdaptiveNavigationScaffold — 5 destinations avec libellés FR', () {
    testWidgets('NavigationBar affiche les 5 labels français', (tester) async {
      await _setViewportWidth(tester, 400);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Biens'), findsOneWidget);
      expect(find.text('Locataires'), findsOneWidget);
      expect(find.text('Baux'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
    });

    testWidgets('NavigationRail étendu (>= 1024 px) affiche aussi les labels', (
      tester,
    ) async {
      await _setViewportWidth(tester, 1200);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Baux'), findsOneWidget);
    });
  });

  group('AdaptiveNavigationScaffold — sélection de destination', () {
    testWidgets('selectedIndex reflète la branche active (accueil = 0)', (
      tester,
    ) async {
      await _setViewportWidth(tester, 400);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter()),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });

    testWidgets(
      'tap sur « Baux » (NavigationBar) → goBranch(3), contenu change',
      (tester) async {
        await _setViewportWidth(tester, 400);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('field_accueil')), findsOneWidget);
        expect(find.byKey(const Key('field_baux')), findsNothing);

        await tester.tap(find.text('Baux'));
        await tester.pumpAndSettle();

        final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.selectedIndex, 3);
        expect(find.byKey(const Key('field_baux')), findsOneWidget);
        expect(find.byKey(const Key('field_accueil')), findsNothing);
      },
    );

    testWidgets('tap sur « Locataires » (NavigationRail) → goBranch(2)', (
      tester,
    ) async {
      await _setViewportWidth(tester, 900);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Locataires'));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
      expect(find.byKey(const Key('field_locataires')), findsOneWidget);
    });
  });

  group('AdaptiveNavigationScaffold — préservation d\'état par branche', () {
    testWidgets(
      'changer de branche PUIS revenir préserve la saisie (indexedStack)',
      (tester) async {
        await _setViewportWidth(tester, 400);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        // Saisit une valeur dans le champ de la branche Accueil.
        await tester.enterText(
          find.byKey(const Key('field_accueil')),
          'valeur-persistee',
        );
        await tester.pump();

        // Bascule sur Biens.
        await tester.tap(find.text('Biens'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('field_accueil')), findsNothing);

        // Revient sur Accueil : la valeur saisie doit être intacte —
        // indexedStack garde le widget vivant (State non détruit), il ne le
        // reconstruit pas comme le ferait un ShellRoute simple. Le TextField
        // n'a pas de controller explicite (état interne à l'EditableText),
        // donc on vérifie le texte affiché à l'écran plutôt que le widget
        // descriptor.
        await tester.tap(find.text('Accueil'));
        await tester.pumpAndSettle();

        expect(find.text('valeur-persistee'), findsOneWidget);
      },
    );
  });

  group('AdaptiveNavigationScaffold — re-tap onglet courant', () {
    testWidgets(
      're-tap sur l\'onglet déjà actif → goBranch avec initialLocation '
      '(retour racine de branche)',
      (tester) async {
        await _setViewportWidth(tester, 400);
        final router = _buildTestRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/accueil',
        );

        // Re-tap sur Accueil (déjà actif) : initialLocation: true → même
        // route racine, comportement "pop to root" (idempotent ici car pas
        // de sous-pile factice, mais couvre le contrat de l'API).
        await tester.tap(find.text('Accueil'));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/accueil',
        );
      },
    );
  });
}

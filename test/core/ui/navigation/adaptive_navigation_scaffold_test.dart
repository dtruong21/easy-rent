/// Tests widget pour [AdaptiveNavigationScaffold] (FEAT-026).
///
/// Le shell est exercé via un [StatefulShellRoute.indexedStack] minimal à 5
/// branches factices (contenu trivial) — on teste le MÉCANISME du shell
/// (NavigationBar/Rail selon largeur, goBranch, préservation d'état, rail
/// repliable + action simulateur), pas les pages métier réelles (couvertes
/// par leurs propres tests + par `shell_branch_state_test.dart`).
library;

import 'package:easyrent/core/ui/navigation/adaptive_navigation_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Router de test — 5 branches factices avec un champ de saisie chacune, pour
// pouvoir prouver la préservation d'état par indexedStack. + une route plate
// /simulator (hors shell) pour tester l'action épinglée du rail.
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
      // Hors shell (comme le vrai routeur) : le simulateur.
      GoRoute(
        path: '/simulator',
        builder: (context, state) =>
            const Scaffold(body: Text('page simulateur')),
      ),
    ],
  );
}

Future<void> _pumpApp(WidgetTester tester, GoRouter router) {
  return tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Rail replié par défaut (aucune préférence persistée).
    SharedPreferences.setMockInitialValues({});
  });

  group(
    'AdaptiveNavigationScaffold — bascule NavigationBar / NavigationRail',
    () {
      testWidgets('< 600 px → NavigationBar présente, NavigationRail absente', (
        tester,
      ) async {
        await _setViewportWidth(tester, 400);
        await _pumpApp(tester, _buildTestRouter());
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
          await _pumpApp(tester, _buildTestRouter());
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
        await _pumpApp(tester, _buildTestRouter());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('adaptive_nav_rail')), findsOneWidget);
        expect(find.byKey(const Key('adaptive_nav_bar')), findsNothing);
      });
    },
  );

  group('AdaptiveNavigationScaffold — 5 destinations avec libellés FR', () {
    testWidgets('NavigationBar affiche les 5 labels français', (tester) async {
      await _setViewportWidth(tester, 400);
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Biens'), findsOneWidget);
      expect(find.text('Locataires'), findsOneWidget);
      expect(find.text('Baux'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
    });

    testWidgets('NavigationRail replié affiche les libellés (labelType.all)', (
      tester,
    ) async {
      await _setViewportWidth(tester, 1200);
      await _pumpApp(tester, _buildTestRouter());
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
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });

    testWidgets(
      'tap sur « Baux » (NavigationBar) → goBranch(3), contenu change',
      (tester) async {
        await _setViewportWidth(tester, 400);
        await _pumpApp(tester, _buildTestRouter());
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
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Locataires'));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
      expect(find.byKey(const Key('field_locataires')), findsOneWidget);
    });
  });

  group('AdaptiveNavigationScaffold — rail repliable (bouton menu)', () {
    testWidgets('replié par défaut (extended == false)', (tester) async {
      await _setViewportWidth(tester, 1200);
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(find.byKey(const Key('rail_menu_toggle')), findsOneWidget);
    });

    testWidgets(
      'tap bouton menu → déplie (extended == true), re-tap → replie',
      (tester) async {
        await _setViewportWidth(tester, 1200);
        await _pumpApp(tester, _buildTestRouter());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('rail_menu_toggle')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isTrue,
        );

        await tester.tap(find.byKey(const Key('rail_menu_toggle')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isFalse,
        );
      },
    );

    testWidgets('préférence persistée « déplié » → rail étendu au montage', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'nav_rail_expanded': true});
      await _setViewportWidth(tester, 1200);
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );
    });
  });

  group('AdaptiveNavigationScaffold — action simulateur (rail)', () {
    testWidgets('présente dans le rail, absente de la NavigationBar', (
      tester,
    ) async {
      await _setViewportWidth(tester, 900);
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rail_simulator_action')), findsOneWidget);
    });

    testWidgets('tap → navigue vers /simulator (hors shell)', (tester) async {
      await _setViewportWidth(tester, 900);
      await _pumpApp(tester, _buildTestRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rail_simulator_action')));
      await tester.pumpAndSettle();

      expect(find.text('page simulateur'), findsOneWidget);
    });
  });

  group('AdaptiveNavigationScaffold — préservation d\'état par branche', () {
    testWidgets(
      'changer de branche PUIS revenir préserve la saisie (indexedStack)',
      (tester) async {
        await _setViewportWidth(tester, 400);
        await _pumpApp(tester, _buildTestRouter());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_accueil')),
          'valeur-persistee',
        );
        await tester.pump();

        await tester.tap(find.text('Biens'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('field_accueil')), findsNothing);

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
        await _pumpApp(tester, router);
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/accueil',
        );

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

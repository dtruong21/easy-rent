/// Preuve bout-en-bout FEAT-043 : la bascule de langue (via [localeProvider],
/// même mécanisme que le sélecteur `/profile`) change une chaîne témoin de
/// l'UI, sans reconstruire l'app.
///
/// Écran témoin : la navigation shell (`AdaptiveNavigationScaffold`), migrée
/// en l10n (`navHome`, `navProperties`, …) — voir
/// `lib/core/ui/navigation/adaptive_navigation_scaffold.dart`.
///
/// Le harnais reproduit le wiring i18n de `main.dart` (délégués,
/// `supportedLocales`, `locale: ref.watch(localeProvider)`) sans dépendre du
/// vrai `appRouterProvider` (Firebase non initialisé en test unitaire).
///
/// Note : la locale « device » du harnais `flutter_test` est `en_US`
/// (fixe), qui EST dans `supportedLocales` — la résolution système
/// (`resolveLocale`) n'est donc jamais exercée par CE test (couverte
/// séparément, en pur, par `test/core/i18n/locale_resolution_test.dart`).
/// Ici on force `locale: const Locale('fr')` en absence d'override pour
/// isoler et prouver le comportement qui compte réellement pour
/// l'utilisateur : l'override manuel (sélecteur `/profile`) et sa bascule
/// runtime.
library;

import 'package:easyrent/core/i18n/locale_provider.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/navigation/adaptive_navigation_scaffold.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _brancheFactice(String label) =>
    Scaffold(body: Center(child: Text(label)));

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

/// Calque minimal de `BaillanApp` (main.dart) : watche [localeProvider],
/// wiring i18n identique (délégués, `supportedLocales`,
/// `localeResolutionCallback`). `locale: null` (préférence « Système » côté
/// [localeProvider]) retombe ici sur `Locale('fr')` — forcé explicitement
/// pour rendre le test déterministe indépendamment de la locale de la
/// machine qui exécute la suite (voir note de fichier ci-dessus).
class _TestApp extends ConsumerWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider) ?? const Locale('fr');
    return MaterialApp.router(
      routerConfig: router,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeResolutionCallback: resolveLocale,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'défaut (aucun override localeProvider) → libellés de navigation en '
    'français',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(router: _buildTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Biens'), findsOneWidget);
      expect(find.text('Locataires'), findsOneWidget);
      expect(find.text('Baux'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
    },
  );

  testWidgets(
    'override localeProvider(en) → libellés de navigation en anglais',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(router: _buildTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('en'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Properties'), findsOneWidget);
      expect(find.text('Tenants'), findsOneWidget);
      expect(find.text('Leases'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // Pas de résidu FR : la bascule remplace, elle n'additionne pas.
      expect(find.text('Accueil'), findsNothing);
    },
  );

  testWidgets(
    'runtime switch — en → fr revient aux libellés français sans remonter '
    'le widget',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(router: _buildTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('fr'));
      await tester.pumpAndSettle();

      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );
}

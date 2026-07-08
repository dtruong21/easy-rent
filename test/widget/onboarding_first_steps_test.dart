/// Tests widget pour [OnboardingFirstSteps].
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/onboarding_first_steps.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap() {
  return MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const OnboardingFirstSteps(),
        ),
        GoRoute(
          path: '/properties/new',
          builder: (context, state) => const Scaffold(body: Text('properties')),
        ),
        GoRoute(
          path: '/tenants/new',
          builder: (context, state) => const Scaffold(body: Text('tenants')),
        ),
        GoRoute(
          path: '/leases/new',
          builder: (context, state) => const Scaffold(body: Text('leases')),
        ),
      ],
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
  );
}

void main() {
  group('OnboardingFirstSteps', () {
    testWidgets('affiche les 3 étapes', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Ajouter un bien'), findsOneWidget);
      expect(find.text('Ajouter un locataire'), findsOneWidget);
      expect(find.text('Créer un bail'), findsOneWidget);
    });

    testWidgets('affiche le titre de bienvenue', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue ! Premiers pas'), findsOneWidget);
    });

    testWidgets('tap étape 1 → navigation /properties/new', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un bien'));
      await tester.pumpAndSettle();
      expect(find.text('properties'), findsOneWidget);
    });

    testWidgets('tap étape 2 → navigation /tenants/new', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un locataire'));
      await tester.pumpAndSettle();
      expect(find.text('tenants'), findsOneWidget);
    });

    testWidgets('tap étape 3 → navigation /leases/new', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer un bail'));
      await tester.pumpAndSettle();
      expect(find.text('leases'), findsOneWidget);
    });
  });
}

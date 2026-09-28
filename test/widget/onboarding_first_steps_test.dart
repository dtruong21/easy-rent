/// Tests widget pour [OnboardingFirstSteps].
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/dashboard/application/onboarding_dismissed_provider.dart';
import 'package:easyrent/features/dashboard/domain/onboarding_progress.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/onboarding_first_steps.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fullProgress = OnboardingProgress(
  hasProperty: true,
  hasTenant: true,
  hasLease: true,
  hasPayment: true,
  hasReceipt: true,
  firstLeaseId: 'lease-1',
);

Widget _wrap({
  required OnboardingProgress progress,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                OnboardingFirstSteps(progress: progress),
          ),
          GoRoute(
            path: '/properties/new',
            builder: (context, state) =>
                const Scaffold(body: Text('properties')),
          ),
          GoRoute(
            path: '/tenants/new',
            builder: (context, state) => const Scaffold(body: Text('tenants')),
          ),
          GoRoute(
            path: '/leases/new',
            builder: (context, state) => const Scaffold(body: Text('leases')),
          ),
          GoRoute(
            path: '/leases/:leaseId/payments/new',
            builder: (context, state) => const Scaffold(body: Text('payments')),
          ),
          GoRoute(
            path: '/leases/:leaseId',
            builder: (context, state) =>
                const Scaffold(body: Text('lease detail')),
          ),
        ],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingFirstSteps', () {
    testWidgets('affiche les 5 étapes', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('Ajouter un bien'), findsOneWidget);
      expect(find.text('Ajouter un locataire'), findsOneWidget);
      expect(find.text('Créer un bail'), findsOneWidget);
      expect(find.text('Enregistrer un paiement'), findsOneWidget);
      expect(find.text('Générer une quittance'), findsOneWidget);
    });

    testWidgets('affiche le titre de bienvenue', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue ! Premiers pas'), findsOneWidget);
    });

    testWidgets('affiche la progression "2 / 5"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: true,
            hasTenant: true,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);
    });

    testWidgets('étape complétée : coche visible, pas de chevron', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: true,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final propertyTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Ajouter un bien'),
          matching: find.byType(ListTile),
        ),
      );
      expect(propertyTile.trailing, isNull);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('étapes 4-5 désactivées sans bail', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: true,
            hasTenant: true,
            hasLease: true,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paymentTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Enregistrer un paiement'),
          matching: find.byType(ListTile),
        ),
      );
      final receiptTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Générer une quittance'),
          matching: find.byType(ListTile),
        ),
      );
      expect(paymentTile.enabled, isFalse);
      expect(receiptTile.enabled, isFalse);
    });

    testWidgets('étapes 4-5 activées avec un bail', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: true,
            hasTenant: true,
            hasLease: true,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: 'lease-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paymentTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Enregistrer un paiement'),
          matching: find.byType(ListTile),
        ),
      );
      final receiptTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Générer une quittance'),
          matching: find.byType(ListTile),
        ),
      );
      expect(paymentTile.enabled, isTrue);
      expect(receiptTile.enabled, isTrue);
    });

    testWidgets('tap étape 1 → navigation /properties/new', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un bien'));
      await tester.pumpAndSettle();
      expect(find.text('properties'), findsOneWidget);
    });

    testWidgets('tap étape 2 → navigation /tenants/new', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un locataire'));
      await tester.pumpAndSettle();
      expect(find.text('tenants'), findsOneWidget);
    });

    testWidgets('tap étape 3 → navigation /leases/new', (tester) async {
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer un bail'));
      await tester.pumpAndSettle();
      expect(find.text('leases'), findsOneWidget);
    });

    testWidgets('tap étape 4 → navigation paiement (avec bail)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(progress: _fullProgress));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer un paiement'));
      await tester.pumpAndSettle();
      expect(find.text('payments'), findsOneWidget);
    });

    testWidgets('tap étape 5 → fiche du bail (liste des paiements)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(progress: _fullProgress));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer une quittance'));
      await tester.pumpAndSettle();
      expect(find.text('lease detail'), findsOneWidget);
    });

    testWidgets('tap "Passer" appelle dismiss', (tester) async {
      final notifier = OnboardingDismissedNotifier(
        OnboardingDismissedStorage(),
      );
      await tester.pumpWidget(
        _wrap(
          progress: const OnboardingProgress(
            hasProperty: false,
            hasTenant: false,
            hasLease: false,
            hasPayment: false,
            hasReceipt: false,
            firstLeaseId: null,
          ),
          overrides: [
            onboardingDismissedProvider.overrideWith((ref) => notifier),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(notifier.state, isFalse);
      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();
      expect(notifier.state, isTrue);
    });
  });
}

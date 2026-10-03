/// Tests widget de [ProCancelPage] (retour d'un checkout Stripe annulé).
///
/// Sur les apps iOS/Android (conformité stores), la page ne propose plus de
/// bouton « Réessayer » : il renverrait vers `/pro`, donc vers un achat hors
/// achat intégré.
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_cancel_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildPage() {
  final router = GoRouter(
    initialLocation: '/pro/cancel',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (_, _) => const Scaffold(body: Text('dashboard-stub')),
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) => const Scaffold(body: Text('pro-stub')),
        routes: [
          GoRoute(path: 'cancel', builder: (_, _) => const ProCancelPage()),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
  );
}

void main() {
  group('ProCancelPage — web (Stripe)', () {
    testWidgets('« Réessayer » renvoie vers /pro', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Paiement annulé'), findsOneWidget);
      expect(find.text('Retour'), findsOneWidget);
      expect(find.byKey(const Key('btn_pro_cancel_retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_pro_cancel_retry')));
      await tester.pumpAndSettle();
      expect(find.text('pro-stub'), findsOneWidget);
    });
  });

  group('ProCancelPage — app store (iOS/Android)', () {
    setUp(() => debugIsStoreAppOverride = true);
    tearDown(() => debugIsStoreAppOverride = false);

    testWidgets('aucun bouton vers /pro, retour au tableau de bord conservé', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_pro_cancel_retry')), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Retour'), findsOneWidget);

      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('dashboard-stub'), findsOneWidget);
    });
  });
}

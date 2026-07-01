/// Tests widget pour [AnonDemoBanner] (BAILLAN-M1).
library;

import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/auth/presentation/widgets/anon_demo_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildApp({
  required SessionState sessionState,
  DateTime? anonExpiresAt,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: AnonDemoBanner()),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const Scaffold(body: Text('Signup')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sessionStateProvider.overrideWithValue(sessionState),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(
          LandlordTierSnapshot(
            tier: sessionState == SessionState.anonymous
                ? SubscriptionTier.anonymous
                : SubscriptionTier.free,
            anonExpiresAt: anonExpiresAt,
          ),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('AnonDemoBanner — visibilité selon sessionState', () {
    testWidgets('invisible si fullyAuthenticated', (tester) async {
      await tester.pumpWidget(
        _buildApp(sessionState: SessionState.fullyAuthenticated),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anon_demo_banner')), findsNothing);
    });

    testWidgets('invisible si unauthenticated', (tester) async {
      await tester.pumpWidget(
        _buildApp(sessionState: SessionState.unauthenticated),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anon_demo_banner')), findsNothing);
    });

    testWidgets('visible si anonymous, ton neutre par défaut', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.anonymous,
          anonExpiresAt: DateTime.now().add(const Duration(days: 10)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anon_demo_banner')), findsOneWidget);
      expect(find.textContaining('Mode démo'), findsOneWidget);
      expect(find.byKey(const Key('anon_expiry_warning_dialog')), findsNothing);
    });
  });

  group('AnonDemoBanner — escalade de tonalité', () {
    testWidgets('ton alarmé à J-3', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.anonymous,
          anonExpiresAt: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('expire dans'), findsOneWidget);
    });

    testWidgets('modal bloquante affichée en plus du bandeau à J-1 (<24h)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.anonymous,
          anonExpiresAt: DateTime.now().add(const Duration(hours: 18)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anon_demo_banner')), findsOneWidget);
      expect(
        find.byKey(const Key('anon_expiry_warning_dialog')),
        findsOneWidget,
      );
    });

    testWidgets('CTA "Créer un compte" du bandeau navigue vers /signup', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.anonymous,
          anonExpiresAt: DateTime.now().add(const Duration(days: 10)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('anon_demo_banner_cta')));
      await tester.pumpAndSettle();

      expect(find.text('Signup'), findsOneWidget);
    });
  });
}

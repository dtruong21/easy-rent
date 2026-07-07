/// Tests widget de [DeleteAccountRequestPage] (FEAT-045) — page publique
/// `/delete-account` exigée par Google Play (Account deletion).
///
/// Couvre les 3 branches de session :
/// - non connecté → étapes + bouton vers /login
/// - compte complet → bouton vers /profile/delete-account
/// - anonyme → suppression directe de l'essai (confirm dialog + purge)
library;

import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/auth/presentation/delete_account_request_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuthRepository implements AuthRepository {
  final calls = <String>[];

  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentUser => null;

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _buildPage({
  required SessionState sessionState,
  required _FakeAuthRepository authRepo,
}) {
  final router = GoRouter(
    initialLocation: '/delete-account',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('landing-stub')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('login-stub')),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountRequestPage(),
      ),
      GoRoute(
        path: '/profile/delete-account',
        builder: (context, state) =>
            const Scaffold(body: Text('delete-page-stub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      sessionStateProvider.overrideWithValue(sessionState),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    'contenu : nom Baillan, étapes in-app et mention rétention quittances',
    (tester) async {
      final authRepo = _FakeAuthRepository();
      await tester.pumpWidget(
        _buildPage(
          sessionState: SessionState.unauthenticated,
          authRepo: authRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Supprimer votre compte Baillan'), findsOneWidget);
      expect(find.textContaining('Supprimer mon compte'), findsWidgets);
      expect(find.textContaining('loi n° 89-462 du 6 juillet'), findsOneWidget);
      expect(find.text('Comment procéder'), findsOneWidget);
    },
  );

  testWidgets('non connecté → bouton vers la connexion', (tester) async {
    final authRepo = _FakeAuthRepository();
    await tester.pumpWidget(
      _buildPage(
        sessionState: SessionState.unauthenticated,
        authRepo: authRepo,
      ),
    );
    await tester.pumpAndSettle();

    final loginBtn = find.byKey(const Key('btn_delete_request_login'));
    expect(loginBtn, findsOneWidget);

    await tester.ensureVisible(loginBtn);
    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    expect(find.text('login-stub'), findsOneWidget);
  });

  testWidgets('compte complet → bouton direct vers /profile/delete-account', (
    tester,
  ) async {
    final authRepo = _FakeAuthRepository();
    await tester.pumpWidget(
      _buildPage(
        sessionState: SessionState.fullyAuthenticated,
        authRepo: authRepo,
      ),
    );
    await tester.pumpAndSettle();

    final goBtn = find.byKey(const Key('btn_delete_request_go_profile'));
    expect(goBtn, findsOneWidget);

    await tester.ensureVisible(goBtn);
    await tester.tap(goBtn);
    await tester.pumpAndSettle();

    expect(find.text('delete-page-stub'), findsOneWidget);
  });

  group('session anonyme (essai)', () {
    testWidgets('annuler le dialog → aucune purge', (tester) async {
      final authRepo = _FakeAuthRepository();
      await tester.pumpWidget(
        _buildPage(sessionState: SessionState.anonymous, authRepo: authRepo),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(const Key('btn_delete_request_anonymous'));
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Supprimer votre essai ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_delete_request_anon_cancel')));
      await tester.pumpAndSettle();

      expect(authRepo.calls, isEmpty);
    });

    testWidgets('confirmer → purge directe (sans re-auth), retour landing', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository();
      await tester.pumpWidget(
        _buildPage(sessionState: SessionState.anonymous, authRepo: authRepo),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(const Key('btn_delete_request_anonymous'));
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('btn_delete_request_anon_confirm')),
      );
      await tester.pumpAndSettle();

      expect(authRepo.calls, ['deleteAccount']);
      expect(
        find.text('Votre essai et ses données ont été supprimés.'),
        findsOneWidget,
      );
      // Pas de navigation explicite : la page publique reste affichée et se
      // re-rend seule au flip de session (anonymous → unauthenticated).
      expect(find.byType(DeleteAccountRequestPage), findsOneWidget);
    });
  });
}

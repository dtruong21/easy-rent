/// Tests widget de [DeleteAccountPage] (FEAT-045).
///
/// Couvre :
/// - Contenu d'avertissement : conséquences + mention rétention quittances
///   (exigence stores : la rétention doit être ANNONCÉE dans le flux)
/// - Re-auth adaptée au provider (mot de passe / Google / Apple)
/// - Double gate : case de consentement + dialog de confirmation finale
/// - Ordre des appels repo (reauth → revoke Apple → purge)
/// - Chemin malheureux (mot de passe erroné → erreur, pas de purge)
library;

import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/profile/presentation/delete_account_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake AuthRepository — seuls les membres du flux FEAT-045 sont réels,
// le reste passe par noSuchMethod (jamais appelé par cette page).
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final User? _user;
  final calls = <String>[];

  FirebaseAuthException? reauthPasswordError;
  String? appleAuthorizationCode;

  @override
  Stream<User?> get authStateChanges => Stream.value(_user);

  @override
  User? get currentUser => _user;

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {
    calls.add('reauthPassword($currentPassword)');
    final err = reauthPasswordError;
    if (err != null) throw err;
  }

  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async {
    calls.add('reauthOAuth($providerId)');
    return providerId == 'apple.com' ? appleAuthorizationCode : null;
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    calls.add('revokeApple($authorizationCode)');
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

UserInfo _providerInfo(String providerId) => UserInfo.fromJson({
  'uid': 'uid-1',
  'email': 'test@example.com',
  'displayName': null,
  'photoUrl': null,
  'phoneNumber': null,
  'isAnonymous': false,
  'isEmailVerified': true,
  'providerId': providerId,
  'tenantId': null,
  'refreshToken': null,
  'creationTimestamp': null,
  'lastSignInTimestamp': null,
});

MockUser _userWithProvider(String providerId) => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'test@example.com',
  providerData: [_providerInfo(providerId)],
);

Widget _buildPage({required _FakeAuthRepository authRepo}) {
  final router = GoRouter(
    initialLocation: '/profile/delete-account',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('landing-stub')),
      ),
      GoRoute(
        path: '/profile/delete-account',
        builder: (context, state) => const DeleteAccountPage(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(authRepo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Remplit le prérequis commun : coche la case de consentement.
Future<void> _acknowledge(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('check_delete_account_ack')));
  await tester.tap(find.byKey(const Key('check_delete_account_ack')));
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('btn_delete_account_submit')),
  );
  await tester.tap(find.byKey(const Key('btn_delete_account_submit')));
  await tester.pumpAndSettle();
}

Future<void> _confirmDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn_delete_account_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('contenu d\'avertissement', () {
    testWidgets(
      'conséquences + mention de rétention légale des quittances affichées',
      (tester) async {
        final authRepo = _FakeAuthRepository(_userWithProvider('password'));
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        expect(
          find.text('Cette action est immédiate et irréversible'),
          findsOneWidget,
        );
        // Exigence stores : rétention quittances annoncée dans le flux.
        expect(
          find.byKey(const Key('box_receipts_retention_notice')),
          findsOneWidget,
        );
        expect(
          find.textContaining('loi n° 89-462 du 6 juillet 1989'),
          findsOneWidget,
        );
        expect(find.textContaining('5 ans'), findsOneWidget);
      },
    );
  });

  group('compte email (password)', () {
    testWidgets('bouton désactivé sans case cochée ni mot de passe', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_userWithProvider('password'));
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('field_delete_account_password')),
        findsOneWidget,
      );
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_delete_account_submit')),
      );
      expect(btn.onPressed, isNull);

      // Case cochée mais mot de passe vide → toujours désactivé.
      await _acknowledge(tester);
      final btnAfterAck = tester.widget<FilledButton>(
        find.byKey(const Key('btn_delete_account_submit')),
      );
      expect(btnAfterAck.onPressed, isNull);
    });

    testWidgets('annuler le dialog → aucun appel repo', (tester) async {
      final authRepo = _FakeAuthRepository(_userWithProvider('password'));
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_delete_account_password')),
        'S3cret!!',
      );
      await _acknowledge(tester);
      await _tapSubmit(tester);

      expect(find.text('Supprimer définitivement ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_delete_account_cancel')));
      await tester.pumpAndSettle();

      expect(authRepo.calls, isEmpty);
    });

    testWidgets(
      'confirmation → reauth mot de passe puis purge, snackbar, retour landing',
      (tester) async {
        final authRepo = _FakeAuthRepository(_userWithProvider('password'));
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_delete_account_password')),
          'S3cret!!',
        );
        await _acknowledge(tester);
        await _tapSubmit(tester);
        await _confirmDialog(tester);

        expect(authRepo.calls, ['reauthPassword(S3cret!!)', 'deleteAccount']);
        expect(
          find.text('Votre compte a été supprimé. Au revoir.'),
          findsOneWidget,
        );
        expect(find.text('landing-stub'), findsOneWidget);
      },
    );

    testWidgets('mot de passe erroné → erreur affichée, pas de purge', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_userWithProvider('password'))
        ..reauthPasswordError = FirebaseAuthException(code: 'wrong-password');
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_delete_account_password')),
        'Wrong!!1',
      );
      await _acknowledge(tester);
      await _tapSubmit(tester);
      await _confirmDialog(tester);

      expect(find.byKey(const Key('txt_delete_account_error')), findsOneWidget);
      expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
      expect(authRepo.calls, isNot(contains('deleteAccount')));
    });
  });

  group('comptes sociaux', () {
    testWidgets(
      'Google : info re-auth OAuth (pas de champ mot de passe), ordre des appels',
      (tester) async {
        final authRepo = _FakeAuthRepository(_userWithProvider('google.com'));
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('field_delete_account_password')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('txt_delete_account_reauth_oauth')),
          findsOneWidget,
        );
        expect(find.textContaining('Google'), findsWidgets);

        await _acknowledge(tester);
        await _tapSubmit(tester);
        await _confirmDialog(tester);

        expect(authRepo.calls, ['reauthOAuth(google.com)', 'deleteAccount']);
      },
    );

    testWidgets(
      'Apple avec authorizationCode : révocation token AVANT la purge '
      '(App Store 5.1.1(v))',
      (tester) async {
        final authRepo = _FakeAuthRepository(_userWithProvider('apple.com'))
          ..appleAuthorizationCode = 'code-abc';
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        await _acknowledge(tester);
        await _tapSubmit(tester);
        await _confirmDialog(tester);

        expect(authRepo.calls, [
          'reauthOAuth(apple.com)',
          'revokeApple(code-abc)',
          'deleteAccount',
        ]);
      },
    );

    testWidgets('Apple sans authorizationCode (web) : purge sans révocation', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_userWithProvider('apple.com'));
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await _acknowledge(tester);
      await _tapSubmit(tester);
      await _confirmDialog(tester);

      expect(authRepo.calls, ['reauthOAuth(apple.com)', 'deleteAccount']);
    });
  });
}

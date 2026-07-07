/// Tests widget de [ChangePasswordPage].
///
/// Couvre :
/// - Gating par provider (password/Google/Apple/anonyme) : formulaire monté
///   uniquement pour un compte email, message sobre sinon (garde-fou accès
///   URL direct)
/// - Succès, erreurs de changement de mot de passe
/// - État submitting
library;

import 'dart:async';

import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/profile/presentation/change_password_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake AuthRepository
// ---------------------------------------------------------------------------

/// Fake [AuthRepository] dont on contrôle le [User] exposé (pour
/// [hasPasswordProvider]) et les 2 appels du flow de changement de mot de
/// passe in-app (FEAT-025).
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final User? _user;

  bool reauthenticateCalled = false;
  bool updatePasswordCalled = false;
  String? lastCurrentPassword;
  String? lastNewPassword;

  /// Si non-null, jeté par [reauthenticateWithPassword].
  FirebaseAuthException? reauthenticateError;

  /// Si non-null, [reauthenticateWithPassword] attend que ce [Completer]
  /// soit complété avant de retourner — permet d'observer l'état
  /// `submitting` dans les tests (sans ce hook, le Future se résoudrait
  /// avant le prochain `pump()`).
  Completer<void>? reauthenticateGate;

  @override
  Stream<User?> get authStateChanges => Stream.value(_user);

  @override
  User? get currentUser => _user;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {}

  @override
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> linkAnonymousWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required bool rgpdConsent,
  }) async {}

  @override
  Future<void> linkAnonymousWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> linkAnonymousWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'test@example.com';

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {
    reauthenticateCalled = true;
    lastCurrentPassword = currentPassword;
    final gate = reauthenticateGate;
    if (gate != null) await gate.future;
    final err = reauthenticateError;
    if (err != null) throw err;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalled = true;
    lastNewPassword = newPassword;
  }

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Faker le User / providerData (firebase_auth_mocks)
// ---------------------------------------------------------------------------

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

MockUser _passwordUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'test@example.com',
  providerData: [_providerInfo('password')],
);

MockUser _googleUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'g@example.com',
  providerData: [_providerInfo('google.com')],
);

MockUser _appleUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'a@example.com',
  providerData: [_providerInfo('apple.com')],
);

MockUser _anonUser() => MockUser(isAnonymous: true, uid: 'uid-a');

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildPage({required _FakeAuthRepository authRepo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ChangePasswordPage(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(authRepo)],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('titre "Changer le mot de passe" affiché', (tester) async {
    final authRepo = _FakeAuthRepository(_passwordUser());
    await tester.pumpWidget(_buildPage(authRepo: authRepo));
    await tester.pumpAndSettle();

    expect(find.text('Changer le mot de passe'), findsOneWidget);
  });

  group('gating hasPasswordProvider', () {
    testWidgets('compte email → formulaire monté', (tester) async {
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_current_password')), findsOneWidget);
      expect(find.byKey(const Key('field_new_password')), findsOneWidget);
      expect(find.byKey(const Key('field_confirm_password')), findsOneWidget);
      expect(find.byKey(const Key('btn_change_password')), findsOneWidget);
      expect(find.byKey(const Key('txt_no_password_notice')), findsNothing);
    });

    testWidgets('compte Google → message sobre affiché, formulaire absent', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_googleUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('txt_no_password_notice')), findsOneWidget);
      expect(
        find.text(
          'Le mot de passe de ce compte est géré par votre fournisseur de '
          'connexion.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });

    testWidgets('compte Apple → message sobre affiché, formulaire absent', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_appleUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('txt_no_password_notice')), findsOneWidget);
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });

    testWidgets('session anonyme → message sobre affiché, formulaire absent', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_anonUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('txt_no_password_notice')), findsOneWidget);
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });
  });

  group('flow de soumission', () {
    testWidgets(
      'succès — repo appelé (reauth puis update), snackbar, champs vidés',
      (tester) async {
        final authRepo = _FakeAuthRepository(_passwordUser());
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_current_password')),
          'OldPassword1',
        );
        await tester.enterText(
          find.byKey(const Key('field_new_password')),
          'NewPassword2',
        );
        await tester.enterText(
          find.byKey(const Key('field_confirm_password')),
          'NewPassword2',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('btn_change_password')),
        );
        await tester.tap(find.byKey(const Key('btn_change_password')));
        await tester.pumpAndSettle();

        expect(authRepo.reauthenticateCalled, isTrue);
        expect(authRepo.lastCurrentPassword, 'OldPassword1');
        expect(authRepo.updatePasswordCalled, isTrue);
        expect(authRepo.lastNewPassword, 'NewPassword2');

        expect(find.text('Mot de passe mis à jour'), findsOneWidget);

        final currentField = tester.widget<TextField>(
          find
              .descendant(
                of: find.byKey(const Key('field_current_password')),
                matching: find.byType(TextField),
              )
              .first,
        );
        expect(currentField.controller?.text ?? '', isEmpty);
      },
    );

    testWidgets(
      'mot de passe actuel erroné → message dédié, updatePassword jamais appelé',
      (tester) async {
        final authRepo = _FakeAuthRepository(_passwordUser())
          ..reauthenticateError = FirebaseAuthException(
            code: 'wrong-password',
            message: 'wrong password',
          );
        await tester.pumpWidget(_buildPage(authRepo: authRepo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_current_password')),
          'WrongPassword1',
        );
        await tester.enterText(
          find.byKey(const Key('field_new_password')),
          'NewPassword2',
        );
        await tester.enterText(
          find.byKey(const Key('field_confirm_password')),
          'NewPassword2',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('btn_change_password')),
        );
        await tester.tap(find.byKey(const Key('btn_change_password')));
        await tester.pumpAndSettle();

        expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
        expect(authRepo.updatePasswordCalled, isFalse);
      },
    );

    testWidgets('invalid-credential → même message dédié que wrong-password', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_passwordUser())
        ..reauthenticateError = FirebaseAuthException(
          code: 'invalid-credential',
          message: 'invalid credential',
        );
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'WrongPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'NewPassword2',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();

      expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
      expect(authRepo.updatePasswordCalled, isFalse);
    });

    testWidgets('nouveau mot de passe == actuel → refusé sans appel repo', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'SamePassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'SamePassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'SamePassword1',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();

      expect(
        find.text('Le nouveau mot de passe doit être différent de l\'actuel.'),
        findsOneWidget,
      );
      expect(authRepo.reauthenticateCalled, isFalse);
      expect(authRepo.updatePasswordCalled, isFalse);
    });

    testWidgets('confirmation différente → message dédié, aucun appel repo', (
      tester,
    ) async {
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'OldPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'Different3',
      );
      await tester.pump();

      // Le bouton est désactivé côté UI (_canSubmit) tant que confirm !=
      // new — pas de tap possible ; on valide simplement l'état désactivé.
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_change_password')),
      );
      expect(btn.onPressed, isNull);
      expect(authRepo.reauthenticateCalled, isFalse);
    });

    testWidgets('bouton désactivé pendant submit', (tester) async {
      final gate = Completer<void>();
      final authRepo = _FakeAuthRepository(_passwordUser())
        ..reauthenticateGate = gate;
      await tester.pumpWidget(_buildPage(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'OldPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'NewPassword2',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();
      // `tap()` n'attend que le geste physique (down/up), pas la résolution
      // du Future retourné par `onPressed` — le submit reste bloqué sur
      // `gate.future` après ce await, ce qui permet d'observer l'état
      // `submitting` de façon déterministe.
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_change_password')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Débloque le submit puis laisse le Future se résoudre pour éviter un
      // timer pending en fin de test.
      gate.complete();
      await tester.pumpAndSettle();
    });
  });
}

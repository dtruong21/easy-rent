import 'package:easyrent/features/auth/application/delete_account_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/delete_account_reauth_method.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// FEAT-045 — dérivation de la méthode de confirmation d'identité depuis les
// providers du user courant (priorité : password > google > apple ; none
// pour anonyme / non connecté).
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final User? _user;

  @override
  Stream<User?> get authStateChanges => Stream.value(_user);

  @override
  User? get currentUser => _user;

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

MockUser _userWith(List<String> providerIds, {bool isAnonymous = false}) =>
    MockUser(
      isAnonymous: isAnonymous,
      uid: 'uid-1',
      email: isAnonymous ? null : 'test@example.com',
      providerData: [for (final id in providerIds) _providerInfo(id)],
    );

DeleteAccountReauthMethod _resolve(User? user) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
    ],
  );
  addTearDown(container.dispose);
  return container.read(deleteAccountReauthMethodProvider);
}

void main() {
  group('deleteAccountReauthMethodProvider', () {
    test('compte email → password', () {
      expect(
        _resolve(_userWith(['password'])),
        DeleteAccountReauthMethod.password,
      );
    });

    test('compte Google seul → google', () {
      expect(
        _resolve(_userWith(['google.com'])),
        DeleteAccountReauthMethod.google,
      );
    });

    test('compte Apple seul → apple', () {
      expect(
        _resolve(_userWith(['apple.com'])),
        DeleteAccountReauthMethod.apple,
      );
    });

    test('multi-providers : password prioritaire sur google/apple', () {
      expect(
        _resolve(_userWith(['google.com', 'password', 'apple.com'])),
        DeleteAccountReauthMethod.password,
      );
    });

    test('multi-providers sociaux : google prioritaire sur apple', () {
      expect(
        _resolve(_userWith(['apple.com', 'google.com'])),
        DeleteAccountReauthMethod.google,
      );
    });

    test('session anonyme → none (aucun credential à re-présenter)', () {
      expect(
        _resolve(_userWith(const [], isAnonymous: true)),
        DeleteAccountReauthMethod.none,
      );
    });

    test('aucun utilisateur → none', () {
      expect(_resolve(null), DeleteAccountReauthMethod.none);
    });
  });
}

import 'package:easyrent/features/auth/application/anon_expiry_renewer.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  _FakeAuthRepository(this._user);
  final User? _user;

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
  Future<void> signOut() async {}

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

class _FakeAnonExpiryWriter implements AnonExpiryWriter {
  int writeCount = 0;
  String? lastUid;
  DateTime? lastExpiry;

  @override
  Future<void> renew(String uid, DateTime newExpiry) async {
    writeCount++;
    lastUid = uid;
    lastExpiry = newExpiry;
  }
}

ProviderContainer _makeContainer({
  required User? user,
  required _FakeAnonExpiryWriter writer,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
      anonExpiryWriterProvider.overrideWithValue(writer),
    ],
  );
  return container;
}

void main() {
  group('AnonExpiryRenewer — session anonyme', () {
    test('1er appel (boot) → 1 write, anonExpiresAt = now + 14j', () async {
      final user = MockUser(isAnonymous: true, uid: 'anon-1');
      final writer = _FakeAnonExpiryWriter();
      final container = _makeContainer(user: user, writer: writer);
      addTearDown(container.dispose);

      final now = DateTime(2026, 7, 1, 10);
      final renewer = container.read(anonExpiryRenewerProvider.notifier)
        ..debugSetClock(() => now);

      await renewer.renewIfNeeded();

      expect(writer.writeCount, 1);
      expect(writer.lastUid, 'anon-1');
      expect(writer.lastExpiry, now.add(anonExpiryWindow));
    });

    test(
      '2e appel 30 min plus tard (< throttle) → 0 write additionnel',
      () async {
        final user = MockUser(isAnonymous: true, uid: 'anon-2');
        final writer = _FakeAnonExpiryWriter();
        final container = _makeContainer(user: user, writer: writer);
        addTearDown(container.dispose);

        var now = DateTime(2026, 7, 1, 10);
        final renewer = container.read(anonExpiryRenewerProvider.notifier)
          ..debugSetClock(() => now);

        await renewer.renewIfNeeded();
        expect(writer.writeCount, 1);

        now = now.add(const Duration(minutes: 30));
        await renewer.renewIfNeeded();
        expect(writer.writeCount, 1, reason: 'throttle actif à 30 min');
      },
    );

    test('2e appel 2h plus tard (> throttle) → 1 write additionnel', () async {
      final user = MockUser(isAnonymous: true, uid: 'anon-3');
      final writer = _FakeAnonExpiryWriter();
      final container = _makeContainer(user: user, writer: writer);
      addTearDown(container.dispose);

      var now = DateTime(2026, 7, 1, 10);
      final renewer = container.read(anonExpiryRenewerProvider.notifier)
        ..debugSetClock(() => now);

      await renewer.renewIfNeeded();
      expect(writer.writeCount, 1);

      now = now.add(const Duration(hours: 2));
      await renewer.renewIfNeeded();
      expect(writer.writeCount, 2, reason: 'throttle expiré après 2h');
      expect(writer.lastExpiry, now.add(anonExpiryWindow));
    });
  });

  group('AnonExpiryRenewer — session non-anonyme ou absente', () {
    test('session fullyAuthenticated → jamais de write', () async {
      final user = MockUser(isAnonymous: false, isEmailVerified: true);
      final writer = _FakeAnonExpiryWriter();
      final container = _makeContainer(user: user, writer: writer);
      addTearDown(container.dispose);

      await container.read(anonExpiryRenewerProvider.notifier).renewIfNeeded();

      expect(writer.writeCount, 0);
    });

    test('aucun user connecté (currentUser null) → jamais de write', () async {
      final writer = _FakeAnonExpiryWriter();
      final container = _makeContainer(user: null, writer: writer);
      addTearDown(container.dispose);

      await container.read(anonExpiryRenewerProvider.notifier).renewIfNeeded();

      expect(writer.writeCount, 0);
    });
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/auth/application/delete_account_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/delete_account_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// FEAT-045 — orchestration de la suppression de compte : ordre
// reauth → (révocation Apple) → purge, et mapping des erreurs FR.
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  final calls = <String>[];

  Exception? reauthPasswordError;
  Exception? deleteError;
  String? appleAuthorizationCode;

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {
    calls.add('reauthPassword($currentPassword)');
    if (reauthPasswordError != null) throw reauthPasswordError!;
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
    if (deleteError != null) throw deleteError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

({ProviderContainer container, _FakeAuthRepository repo}) _make() {
  final repo = _FakeAuthRepository();
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

void main() {
  group('DeleteAccountController — chemins nominaux', () {
    test('password : reauth puis purge, état success', () async {
      final (:container, :repo) = _make();
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithPassword('s3cret!');

      expect(repo.calls, ['reauthPassword(s3cret!)', 'deleteAccount']);
      expect(
        container.read(deleteAccountControllerProvider),
        const DeleteAccountState.success(),
      );
    });

    test('google : reauth OAuth puis purge, jamais de révocation', () async {
      final (:container, :repo) = _make();
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithGoogle();

      expect(repo.calls, ['reauthOAuth(google.com)', 'deleteAccount']);
    });

    test('apple avec authorizationCode : révocation AVANT la purge', () async {
      final (:container, :repo) = _make();
      repo.appleAuthorizationCode = 'code-abc';
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithApple();

      expect(repo.calls, [
        'reauthOAuth(apple.com)',
        'revokeApple(code-abc)',
        'deleteAccount',
      ]);
    });

    test(
      'apple sans authorizationCode (web/Android) : purge sans révocation',
      () async {
        final (:container, :repo) = _make();
        final controller = container.read(
          deleteAccountControllerProvider.notifier,
        );

        await controller.submitWithApple();

        expect(repo.calls, ['reauthOAuth(apple.com)', 'deleteAccount']);
        expect(
          container.read(deleteAccountControllerProvider),
          const DeleteAccountState.success(),
        );
      },
    );

    test('anonyme : purge directe sans réauthentification', () async {
      final (:container, :repo) = _make();
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithoutReauth();

      expect(repo.calls, ['deleteAccount']);
    });
  });

  group('DeleteAccountController — chemins malheureux', () {
    test('mot de passe incorrect → message dédié, pas de purge', () async {
      final (:container, :repo) = _make();
      repo.reauthPasswordError = FirebaseAuthException(code: 'wrong-password');
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithPassword('mauvais');

      expect(repo.calls, ['reauthPassword(mauvais)']);
      expect(
        container.read(deleteAccountControllerProvider),
        const DeleteAccountState.error(
          message: 'Mot de passe actuel incorrect.',
        ),
      );
    });

    test(
      'callable failed-precondition → message session trop ancienne',
      () async {
        final (:container, :repo) = _make();
        repo.deleteError = FirebaseFunctionsException(
          message: 'recent-login-required',
          code: 'failed-precondition',
        );
        final controller = container.read(
          deleteAccountControllerProvider.notifier,
        );

        await controller.submitWithPassword('s3cret!');

        final state = container.read(deleteAccountControllerProvider);
        state.maybeWhen(
          error: (message) => expect(message, contains('trop ancienne')),
          orElse: () => fail('expected error state, got $state'),
        );
      },
    );

    test('erreur réseau callable → message générique réessayer', () async {
      final (:container, :repo) = _make();
      repo.deleteError = FirebaseFunctionsException(
        message: 'internal',
        code: 'internal',
      );
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithGoogle();

      final state = container.read(deleteAccountControllerProvider);
      state.maybeWhen(
        error: (message) => expect(message, contains('réessayer')),
        orElse: () => fail('expected error state, got $state'),
      );
    });

    test('popup OAuth fermée → erreur mappée FR, pas de purge', () async {
      final repo = _ThrowingOAuthRepo(
        FirebaseAuthException(code: 'popup-closed-by-user'),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithGoogle();

      final state = container.read(deleteAccountControllerProvider);
      state.maybeWhen(
        error: (message) => expect(message, 'Connexion Google annulée.'),
        orElse: () => fail('expected error state, got $state'),
      );
      // Le compte n'a jamais été purgé.
      expect(repo.calls, isNot(contains('deleteAccount')));
    });

    test('reset() revient à idle après une erreur', () async {
      final (:container, :repo) = _make();
      repo.reauthPasswordError = FirebaseAuthException(code: 'wrong-password');
      final controller = container.read(
        deleteAccountControllerProvider.notifier,
      );

      await controller.submitWithPassword('mauvais');
      controller.reset();

      expect(
        container.read(deleteAccountControllerProvider),
        const DeleteAccountState.idle(),
      );
    });
  });
}

class _ThrowingOAuthRepo extends _FakeAuthRepository {
  _ThrowingOAuthRepo(this.oauthError);

  final Exception oauthError;

  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async {
    throw oauthError;
  }
}

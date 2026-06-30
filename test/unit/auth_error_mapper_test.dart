import 'package:easyrent/features/auth/data/auth_error_mapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthErrorMapper.fromException (Firebase codes)', () {
    FirebaseAuthException e(String code, [String message = '']) =>
        FirebaseAuthException(code: code, message: message);

    test('invalid-credential → email/mdp incorrect', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-credential')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('wrong-password → email/mdp incorrect', () {
      expect(
        AuthErrorMapper.fromException(e('wrong-password')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('user-not-found → email/mdp incorrect (anti-énumération)', () {
      expect(
        AuthErrorMapper.fromException(e('user-not-found')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('invalid-email → email/mdp incorrect', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-email')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('user-disabled → compte désactivé', () {
      expect(
        AuthErrorMapper.fromException(e('user-disabled')),
        contains('désactivé'),
      );
    });

    test('email-already-in-use → compte déjà existant', () {
      expect(
        AuthErrorMapper.fromException(e('email-already-in-use')),
        contains('Un compte existe déjà'),
      );
    });

    test('weak-password → mot de passe faible', () {
      expect(
        AuthErrorMapper.fromException(e('weak-password')),
        contains('Mot de passe trop faible'),
      );
    });

    test('too-many-requests → trop de demandes', () {
      expect(
        AuthErrorMapper.fromException(e('too-many-requests')),
        contains('Trop de demandes'),
      );
    });

    test('expired-action-code → lien expiré', () {
      expect(
        AuthErrorMapper.fromException(e('expired-action-code')),
        contains('expiré'),
      );
    });

    test('invalid-action-code → lien expiré', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-action-code')),
        contains('expiré'),
      );
    });

    test('network-request-failed → connexion impossible', () {
      expect(
        AuthErrorMapper.fromException(e('network-request-failed')),
        contains('Connexion impossible'),
      );
    });

    test('operation-not-allowed → méthode non activée', () {
      expect(
        AuthErrorMapper.fromException(e('operation-not-allowed')),
        contains('non activée'),
      );
    });

    test('code inconnu → message générique', () {
      expect(
        AuthErrorMapper.fromException(e('unknown_code_xyz')),
        'Une erreur est survenue. Veuillez réessayer.',
      );
    });
  });
}

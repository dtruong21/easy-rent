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

    test('requires-recent-login → invite à se reconnecter (FEAT-025)', () {
      expect(
        AuthErrorMapper.fromException(e('requires-recent-login')),
        'Pour des raisons de sécurité, reconnectez-vous puis réessayez.',
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

  group('AuthErrorMapper.fromException (Google sign-in codes)', () {
    FirebaseAuthException e(String code, [String message = '']) =>
        FirebaseAuthException(code: code, message: message);

    test('popup-closed-by-user → connexion annulée', () {
      expect(
        AuthErrorMapper.fromException(e('popup-closed-by-user')),
        'Connexion annulée.',
      );
    });

    test('popup-blocked → message popup bloquée', () {
      expect(
        AuthErrorMapper.fromException(e('popup-blocked')),
        contains('bloqué la fenêtre de connexion'),
      );
    });

    test('account-exists-with-different-credential → message FR', () {
      expect(
        AuthErrorMapper.fromException(
          e('account-exists-with-different-credential'),
        ),
        contains('Un compte existe déjà avec cet email mais via une autre'),
      );
    });

    test('cancelled-popup-request → message fenêtre déjà ouverte', () {
      expect(
        AuthErrorMapper.fromException(e('cancelled-popup-request')),
        'Une autre fenêtre de connexion est déjà ouverte.',
      );
    });

    test('web-storage-unsupported → message cookies tiers', () {
      expect(
        AuthErrorMapper.fromException(e('web-storage-unsupported')),
        contains('cookies tiers'),
      );
    });

    test('baillan/google-new-user-on-login → invitation à signup', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/google-new-user-on-login')),
        contains('Aucun compte Baillan associé'),
      );
    });

    test(
      'baillan/rgpd-consent-declined → message consentement obligatoire',
      () {
        expect(
          AuthErrorMapper.fromException(e('baillan/rgpd-consent-declined')),
          "Vous devez accepter les conditions générales d'utilisation "
          'et la politique de confidentialité.',
        );
      },
    );

    test('baillan/popup-blocked → message popup bloquée', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/popup-blocked')),
        contains('bloqué la fenêtre Google'),
      );
    });

    test('baillan/popup-closed → connexion annulée', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/popup-closed')),
        'Connexion Google annulée.',
      );
    });
  });

  group('AuthErrorMapper.fromException (OAuth natif mobile, FEAT-024)', () {
    FirebaseAuthException e(String code) => FirebaseAuthException(code: code);

    test('web-context-canceled (Android) → connexion annulée', () {
      expect(
        AuthErrorMapper.fromException(e('web-context-canceled')),
        'Connexion annulée.',
      );
    });

    test('web-context-cancelled (iOS) → connexion annulée', () {
      expect(
        AuthErrorMapper.fromException(e('web-context-cancelled')),
        'Connexion annulée.',
      );
    });
  });
}

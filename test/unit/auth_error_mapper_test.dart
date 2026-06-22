import 'package:easyrent/features/auth/data/auth_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AuthErrorMapper.fromException', () {
    AuthException e(String message, {String? code}) =>
        AuthException(message, code: code);

    test('invalid_credentials code → message email/mdp incorrect', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'invalid_credentials')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('message "invalid login credentials" → email/mdp incorrect', () {
      expect(
        AuthErrorMapper.fromException(e('Invalid login credentials')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('email_not_confirmed code → vérifier email', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'email_not_confirmed')),
        contains('Vérifiez votre email'),
      );
    });

    test('message "email not confirmed" → vérifier email', () {
      expect(
        AuthErrorMapper.fromException(e('Email not confirmed')),
        contains('Vérifiez votre email'),
      );
    });

    test('user_already_exists code → compte déjà existant', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'user_already_exists')),
        contains('Un compte existe déjà'),
      );
    });

    test('email_taken code → compte déjà existant', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'email_taken')),
        contains('Un compte existe déjà'),
      );
    });

    test('email_exists code → compte déjà existant', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'email_exists')),
        contains('Un compte existe déjà'),
      );
    });

    test('message "already registered" → compte déjà existant', () {
      expect(
        AuthErrorMapper.fromException(e('User already registered')),
        contains('Un compte existe déjà'),
      );
    });

    test('weak_password code → mot de passe faible', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'weak_password')),
        contains('Mot de passe trop faible'),
      );
    });

    test('message "weak password" → mot de passe faible', () {
      expect(
        AuthErrorMapper.fromException(e('Password is too weak')),
        contains('Mot de passe trop faible'),
      );
    });

    test('over_email_send_rate_limit code → trop de demandes', () {
      expect(
        AuthErrorMapper.fromException(
          e('', code: 'over_email_send_rate_limit'),
        ),
        contains('Trop de demandes'),
      );
    });

    test('message "rate limit" → trop de demandes', () {
      expect(
        AuthErrorMapper.fromException(e('Email rate limit exceeded')),
        contains('Trop de demandes'),
      );
    });

    test('otp_expired code → lien expiré', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'otp_expired')),
        contains('expiré'),
      );
    });

    test('flow_state_expired code → lien expiré', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'flow_state_expired')),
        contains('expiré'),
      );
    });

    test('message "expired" → lien expiré', () {
      expect(
        AuthErrorMapper.fromException(e('Token has expired')),
        contains('expiré'),
      );
    });

    test('erreur inconnue → message générique', () {
      expect(
        AuthErrorMapper.fromException(e('some unknown error')),
        'Une erreur est survenue. Veuillez réessayer.',
      );
    });

    test('code inconnu → message générique', () {
      expect(
        AuthErrorMapper.fromException(e('', code: 'unknown_code_xyz')),
        'Une erreur est survenue. Veuillez réessayer.',
      );
    });
  });
}

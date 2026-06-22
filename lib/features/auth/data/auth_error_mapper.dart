import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit les [AuthException] Supabase en messages utilisateur français.
///
/// Priorité : code Supabase (stable) > contenu du message (fragile, fallback).
class AuthErrorMapper {
  const AuthErrorMapper._();

  static String fromException(AuthException e) {
    final code = e.code ?? '';
    final message = e.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials') ||
        message.contains('invalid login')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Vérifiez votre email puis cliquez sur le lien de confirmation '
          'avant de vous connecter.';
    }
    if (code == 'user_already_exists' ||
        code == 'email_taken' ||
        code == 'email_exists' ||
        message.contains('already registered') ||
        message.contains('user already registered')) {
      return 'Un compte existe déjà avec cet email. '
          'Connectez-vous ou réinitialisez votre mot de passe.';
    }
    if (code == 'weak_password' ||
        message.contains('weak password') ||
        message.contains('password is too weak') ||
        message.contains('too weak')) {
      return 'Mot de passe trop faible '
          '(8 caractères min, 1 lettre + 1 chiffre).';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'rate_limit_exceeded' ||
        message.contains('rate limit')) {
      return 'Trop de demandes. Réessayez dans quelques minutes.';
    }
    if (code == 'otp_expired' ||
        code == 'flow_state_expired' ||
        message.contains('expired')) {
      return 'Lien de réinitialisation expiré. Demandez-en un nouveau.';
    }
    return 'Une erreur est survenue. Veuillez réessayer.';
  }
}

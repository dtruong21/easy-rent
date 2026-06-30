import 'package:firebase_auth/firebase_auth.dart';

/// Traduit les [FirebaseAuthException] en messages utilisateur français.
///
/// Codes Firebase : https://firebase.google.com/docs/auth/admin/errors
class AuthErrorMapper {
  const AuthErrorMapper._();

  static String fromException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'invalid-email':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email ou mot de passe incorrect.';

      case 'user-disabled':
        return 'Ce compte a été désactivé.';

      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet email. '
            'Connectez-vous ou réinitialisez votre mot de passe.';

      case 'weak-password':
        return 'Mot de passe trop faible '
            '(6 caractères min côté Firebase, 8 + 1 lettre + 1 chiffre côté app).';

      case 'too-many-requests':
        return 'Trop de demandes. Réessayez dans quelques minutes.';

      case 'expired-action-code':
      case 'invalid-action-code':
        return 'Lien de réinitialisation expiré ou invalide. '
            'Demandez-en un nouveau.';

      case 'network-request-failed':
        return 'Connexion impossible. Vérifiez votre accès internet.';

      case 'operation-not-allowed':
        return 'Méthode d\'authentification non activée. '
            'Contactez le support.';

      default:
        return 'Une erreur est survenue. Veuillez réessayer.';
    }
  }
}

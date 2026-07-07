import 'package:firebase_auth/firebase_auth.dart';

import 'apple_auth_exception.dart';
import 'google_auth_exception.dart';

/// Traduit les [FirebaseAuthException] en messages utilisateur français.
///
/// Codes Firebase : https://firebase.google.com/docs/auth/admin/errors
/// Codes Baillan (préfixe `baillan/`) : voir [GoogleAuthErrorCode] et
/// [AppleAuthErrorCode].
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

      case 'requires-recent-login':
        return 'Pour des raisons de sécurité, reconnectez-vous puis '
            'réessayez.';

      case 'expired-action-code':
      case 'invalid-action-code':
        return 'Lien de réinitialisation expiré ou invalide. '
            'Demandez-en un nouveau.';

      case 'network-request-failed':
        return 'Connexion impossible. Vérifiez votre accès internet.';

      case 'operation-not-allowed':
        return 'Méthode d\'authentification non activée. '
            'Contactez le support.';

      // Codes Firebase génériques, émis quel que soit le provider OAuth
      // (Google comme Apple — ex. re-auth de suppression de compte,
      // FEAT-045) : libellés neutres. Les messages spécifiques Google/Apple
      // restent portés par les codes baillan/* posés par les flows dédiés.
      case 'popup-closed-by-user':
        return 'Connexion annulée.';

      case 'popup-blocked':
        return 'Votre navigateur a bloqué la fenêtre de connexion. '
            'Autorisez les pop-ups pour ce site et réessayez.';

      case 'account-exists-with-different-credential':
        return 'Un compte existe déjà avec cet email mais via une autre '
            'méthode. Connectez-vous d\'abord avec votre mot de passe.';

      case 'cancelled-popup-request':
        return 'Une autre fenêtre de connexion est déjà ouverte.';

      case 'web-storage-unsupported':
        return 'Votre navigateur bloque les cookies tiers nécessaires à '
            'Google. Activez-les ou utilisez le formulaire email.';

      // Code Apple spécifique pouvant survenir si l'utilisateur ferme la
      // fenêtre popup Apple avant de valider — synonyme fonctionnel de
      // 'popup-closed-by-user' côté Firebase.
      case 'user-cancelled':
        return 'Connexion Apple annulée.';

      // Flux OAuth natif mobile (signInWithProvider, FEAT-024) :
      // l'utilisateur a refermé le navigateur intégré avant de valider —
      // équivalent mobile de 'popup-closed-by-user'. Deux orthographes :
      // Android émet 'canceled', iOS 'cancelled'.
      case 'web-context-canceled':
      case 'web-context-cancelled':
        return 'Connexion annulée.';

      case GoogleAuthErrorCode.newUserOnLogin:
        return 'Aucun compte Baillan associé à ce Google. '
            'Veuillez d\'abord créer un compte.';

      case GoogleAuthErrorCode.consentDeclined:
        return "Vous devez accepter les conditions générales d'utilisation "
            'et la politique de confidentialité.';

      case GoogleAuthErrorCode.popupBlocked:
        return 'Votre navigateur a bloqué la fenêtre Google. '
            'Autorisez les pop-ups pour ce site et réessayez.';

      case GoogleAuthErrorCode.popupClosed:
        return 'Connexion Google annulée.';

      case AppleAuthErrorCode.newUserOnLogin:
        return 'Aucun compte Baillan associé à cet Apple. '
            'Veuillez d\'abord créer un compte.';

      case AppleAuthErrorCode.consentDeclined:
        return "Vous devez accepter les conditions générales d'utilisation "
            'et la politique de confidentialité.';

      case AppleAuthErrorCode.popupBlocked:
        return 'Votre navigateur a bloqué la fenêtre Apple. '
            'Autorisez les pop-ups pour ce site et réessayez.';

      case AppleAuthErrorCode.popupClosed:
        return 'Connexion Apple annulée.';

      default:
        return 'Une erreur est survenue. Veuillez réessayer.';
    }
  }
}

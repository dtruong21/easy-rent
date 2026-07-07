import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_error.dart';
import 'apple_auth_exception.dart';
import 'google_auth_exception.dart';

/// Traduit les [FirebaseAuthException] en [AuthError] (enum pur,
/// indépendant de la locale d'affichage — FEAT-043 i18n).
///
/// Codes Firebase : https://firebase.google.com/docs/auth/admin/errors
/// Codes Baillan (préfixe `baillan/`) : voir [GoogleAuthErrorCode] et
/// [AppleAuthErrorCode]. La couche présentation route [AuthError] vers un
/// message localisé via `AuthErrorL10n.message`
/// (`lib/features/auth/presentation/auth_error_l10n.dart`).
class AuthErrorMapper {
  const AuthErrorMapper._();

  static AuthError fromException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'invalid-email':
      case 'wrong-password':
      case 'user-not-found':
        return AuthError.invalidCredentials;

      case 'user-disabled':
        return AuthError.userDisabled;

      case 'email-already-in-use':
        return AuthError.emailAlreadyInUse;

      case 'weak-password':
        return AuthError.weakPassword;

      case 'too-many-requests':
        return AuthError.tooManyRequests;

      case 'requires-recent-login':
        return AuthError.requiresRecentLogin;

      case 'expired-action-code':
      case 'invalid-action-code':
        return AuthError.expiredActionCode;

      case 'network-request-failed':
        return AuthError.networkRequestFailed;

      case 'operation-not-allowed':
        return AuthError.operationNotAllowed;

      case 'popup-closed-by-user':
        return AuthError.googlePopupClosed;

      case 'popup-blocked':
        return AuthError.googlePopupBlocked;

      case 'account-exists-with-different-credential':
        return AuthError.accountExistsWithDifferentCredential;

      case 'cancelled-popup-request':
        return AuthError.googlePopupCancelledRequest;

      case 'web-storage-unsupported':
        return AuthError.webStorageUnsupported;

      // Code Apple spécifique pouvant survenir si l'utilisateur ferme la
      // fenêtre popup Apple avant de valider — synonyme fonctionnel de
      // 'popup-closed-by-user' côté Firebase.
      case 'user-cancelled':
        return AuthError.applePopupClosed;

      case GoogleAuthErrorCode.newUserOnLogin:
        return AuthError.googleNewUserOnLogin;

      case GoogleAuthErrorCode.consentDeclined:
        return AuthError.consentRequired;

      case GoogleAuthErrorCode.popupBlocked:
        return AuthError.googlePopupBlocked;

      case GoogleAuthErrorCode.popupClosed:
        return AuthError.googlePopupClosed;

      case AppleAuthErrorCode.newUserOnLogin:
        return AuthError.appleNewUserOnLogin;

      case AppleAuthErrorCode.consentDeclined:
        return AuthError.consentRequired;

      case AppleAuthErrorCode.popupBlocked:
        return AuthError.applePopupBlocked;

      case AppleAuthErrorCode.popupClosed:
        return AuthError.applePopupClosed;

      default:
        return AuthError.unknown;
    }
  }
}

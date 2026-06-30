/// Codes d'erreur synthétiques Baillan pour le flow de connexion Google.
///
/// Préfixés `baillan/` pour ne jamais collisionner avec les codes natifs
/// Firebase Auth (https://firebase.google.com/docs/auth/admin/errors), qui
/// n'ont pas de préfixe ou utilisent `auth/`. Utilisés à la fois côté
/// [FirebaseAuthRepository] (levés via [FirebaseAuthException]) et côté
/// [AuthErrorMapper] (mappés en messages FR).
class GoogleAuthErrorCode {
  const GoogleAuthErrorCode._();

  /// Un compte Google sans compte Baillan existant a tenté de se connecter
  /// via `/login`. Le compte Firebase Auth créé par le popup a été révoqué
  /// (rollback) — aucune création n'est autorisée sans passer par `/signup`
  /// avec consentement RGPD explicite.
  static const String newUserOnLogin = 'baillan/google-new-user-on-login';

  /// La fenêtre popup Google a été bloquée par le navigateur.
  static const String popupBlocked = 'baillan/popup-blocked';

  /// L'utilisateur a fermé la fenêtre popup Google avant de valider.
  static const String popupClosed = 'baillan/popup-closed';

  /// Le consentement RGPD n'a pas été donné avant l'appel à `signUpWithGoogle`.
  static const String consentDeclined = 'baillan/rgpd-consent-declined';
}

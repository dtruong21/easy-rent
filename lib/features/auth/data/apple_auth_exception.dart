/// Codes d'erreur synthétiques Baillan pour le flow de connexion Apple.
///
/// Préfixés `baillan/` pour ne jamais collisionner avec les codes natifs
/// Firebase Auth (https://firebase.google.com/docs/auth/admin/errors), qui
/// n'ont pas de préfixe ou utilisent `auth/`. Utilisés à la fois côté
/// [FirebaseAuthRepository] (levés via [FirebaseAuthException]) et côté
/// [AuthErrorMapper] (mappés en messages FR).
///
/// Fichier séparé de [GoogleAuthErrorCode] (plutôt qu'un partage/refactor en
/// classe commune) pour éviter tout couplage accidentel entre les deux flows
/// OAuth — chacun peut évoluer indépendamment (ex. Apple retire un jour la
/// distinction popup-blocked/closed sans impacter Google).
class AppleAuthErrorCode {
  const AppleAuthErrorCode._();

  /// Un compte Apple sans compte Baillan existant a tenté de se connecter
  /// via `/login`. Le compte Firebase Auth créé par le popup a été révoqué
  /// (rollback) — aucune création n'est autorisée sans passer par `/signup`
  /// avec consentement RGPD explicite.
  static const String newUserOnLogin = 'baillan/apple-new-user-on-login';

  /// La fenêtre popup Apple a été bloquée par le navigateur.
  static const String popupBlocked = 'baillan/apple-popup-blocked';

  /// L'utilisateur a fermé la fenêtre popup Apple avant de valider.
  static const String popupClosed = 'baillan/apple-popup-closed';

  /// Le consentement RGPD n'a pas été donné avant l'appel à `signUpWithApple`.
  static const String consentDeclined = 'baillan/apple-rgpd-consent-declined';
}

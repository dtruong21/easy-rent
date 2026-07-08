/// Erreurs du flux de suppression de compte (FEAT-045), indépendantes de la
/// locale d'affichage (i18n FEAT-043).
///
/// **Périmètre** : les codes Firebase Auth (ré-authentification) et Cloud
/// Functions (callable `deleteAccount`) mappés par
/// `DeleteAccountController._mapAuthError` / `._mapFunctionsError`
/// (`lib/features/auth/application/delete_account_controller.dart`). Enum
/// dédié plutôt que réutilisation de [AuthError] : les libellés du flux de
/// suppression sont propres à ce contexte (« Connexion annulée. » sans nom de
/// provider, garde de fraîcheur `deleteAccount`, message générique
/// « La suppression a échoué… »), distincts de ceux des écrans de connexion.
///
/// **Contrainte technique** : identique au pattern [AuthError]
/// (`auth_error.dart`) — le contrôleur (`StateNotifier`, sans `BuildContext`)
/// stocke le **nom** de cet enum (`DeleteAccountError.xxx.name`, clé technique
/// stable, jamais un message FR) dans `DeleteAccountState.error.message` ; la
/// couche présentation (`DeleteAccountErrorL10n`,
/// `lib/features/auth/presentation/delete_account_error_l10n.dart`) le
/// reconvertit pour l'affichage — widgets consommateurs :
/// `profile/presentation/delete_account_page.dart` (flux in-app) et
/// `auth/presentation/delete_account_request_page.dart` (page publique).
///
/// Aucune dépendance à `BuildContext`/`AppLocalizations` ici (domaine pur),
/// mêmes garanties que [AuthError].
enum DeleteAccountError {
  /// `wrong-password` / `invalid-credential` — ré-authentification par mot de
  /// passe échouée. Même libellé que [AuthError.currentPasswordIncorrect]
  /// (utilisateur déjà connecté qui ne saisit qu'un mot de passe) : le mapping
  /// l10n réutilise la clé ARB `authErrorCurrentPasswordIncorrect` plutôt que
  /// d'en dupliquer une.
  wrongPassword,

  /// `user-mismatch` — le compte ré-authentifié n'est pas celui connecté.
  userMismatch,

  /// Popup/fenêtre OAuth de ré-authentification (Google/Apple) fermée ou
  /// annulée — web (`popup-closed-by-user`, `cancelled-popup-request`,
  /// `user-cancelled`) comme mobile natif (`web-context-canc[e]lled`).
  reauthCancelled,

  /// `popup-blocked` — le navigateur a bloqué la fenêtre OAuth.
  popupBlocked,

  /// `network-request-failed` — échec réseau pendant la ré-authentification.
  network,

  /// Callable `failed-precondition` (garde `recent-login-required`,
  /// `auth_time` > 5 min) : session trop ancienne, redemander une connexion.
  sessionTooOld,

  /// Callable `unavailable` / `deadline-exceeded` — backend injoignable.
  connectionFailed,

  /// Cas par défaut des mappers + échec inattendu du flux. Libellé dédié
  /// « La suppression a échoué… » (distinct de `commonErrorGeneric`).
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `DeleteAccountState.error.message` — retourne [unknown] si absent/invalide
  /// (filet défensif, ne doit jamais arriver en pratique).
  static DeleteAccountError fromCode(String code) {
    return DeleteAccountError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => DeleteAccountError.unknown,
    );
  }
}

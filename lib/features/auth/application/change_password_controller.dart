import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/password_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/change_password_state.dart';

final _log = Logger('ChangePasswordController');

/// Contrôle le formulaire de changement de mot de passe in-app
/// (`ProfileSecuritySection`, FEAT-025).
///
/// Flow Firebase : `reauthenticateWithPassword` (exige le mot de passe
/// actuel — Firebase requiert une session « récente » pour `updatePassword`)
/// puis `updatePassword`. La session courante est conservée (l'utilisateur
/// n'est jamais déconnecté par ce flow).
///
/// Pas d'anti-énumération OWASP ici (contrairement à
/// `ForgotPasswordController`) : l'utilisateur est déjà connecté et connaît
/// son propre compte — un « mot de passe actuel incorrect » est un message
/// honnête et utile, pas une fuite d'information.
class ChangePasswordController extends StateNotifier<ChangePasswordState> {
  ChangePasswordController(this._repository)
    : super(const ChangePasswordState.idle());

  final AuthRepository _repository;

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final passwordError = PasswordValidator.validate(newPassword);
    if (passwordError != null) {
      state = ChangePasswordState.error(message: passwordError);
      return;
    }
    if (newPassword != confirmPassword) {
      state = const ChangePasswordState.error(
        message: 'Les mots de passe ne correspondent pas',
      );
      return;
    }
    if (newPassword == currentPassword) {
      state = const ChangePasswordState.error(
        message: 'Le nouveau mot de passe doit être différent de l\'actuel.',
      );
      return;
    }

    state = const ChangePasswordState.submitting();
    try {
      await _repository.reauthenticateWithPassword(currentPassword);
      await _repository.updatePassword(newPassword);
      state = const ChangePasswordState.success();
      _log.info('Mot de passe mis à jour (in-app)');
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException changePassword (code=${e.code})',
        e,
        st,
      );
      state = ChangePasswordState.error(message: _mapError(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue changePassword', e, st);
      state = const ChangePasswordState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après un succès affiché
  /// via SnackBar, pour éviter qu'un re-listen retriggère l'affichage).
  void reset() => state = const ChangePasswordState.idle();

  /// Mapping spécifique au contexte « mot de passe actuel » : le libellé
  /// générique `AuthErrorMapper` pour `wrong-password`/`invalid-credential`
  /// mentionne « Email », qui n'a pas de sens ici (l'utilisateur est déjà
  /// connecté, il ne saisit qu'un mot de passe). Les autres codes
  /// (`too-many-requests`, `weak-password`, `requires-recent-login`…)
  /// retombent sur le mapper mutualisé.
  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mot de passe actuel incorrect.';
      default:
        return AuthErrorMapper.fromException(e);
    }
  }
}

final changePasswordControllerProvider =
    StateNotifierProvider.autoDispose<
      ChangePasswordController,
      ChangePasswordState
    >((ref) => ChangePasswordController(ref.read(authRepositoryProvider)));

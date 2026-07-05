import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/password_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/reset_password_state.dart';

final _log = Logger('ResetPasswordController');

class ResetPasswordController extends StateNotifier<ResetPasswordState> {
  ResetPasswordController(this._repository)
    : super(const ResetPasswordState.idle());

  final AuthRepository _repository;

  /// Confirme le reset password Firebase via l'oobCode reçu par email.
  ///
  /// Firebase ne maintient pas de "session recovery" comme Supabase —
  /// l'utilisateur n'est PAS signé pendant le reset, il fournit juste le
  /// code one-time + le nouveau password. Une fois validé, il doit se
  /// reconnecter via le formulaire de login standard.
  Future<void> confirmReset({
    required String oobCode,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (oobCode.isEmpty) {
      state = const ResetPasswordState.error(
        message: 'Code de réinitialisation manquant.',
      );
      return;
    }
    final passwordError = PasswordValidator.validate(newPassword);
    if (passwordError != null) {
      state = ResetPasswordState.error(message: passwordError);
      return;
    }
    if (newPassword != confirmPassword) {
      state = const ResetPasswordState.error(
        message: 'Les mots de passe ne correspondent pas',
      );
      return;
    }

    state = const ResetPasswordState.submitting();
    try {
      await _repository.confirmPasswordReset(
        code: oobCode,
        newPassword: newPassword,
      );
      state = const ResetPasswordState.success();
      _log.info('Mot de passe mis à jour via oobCode');
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException resetPassword (code=${e.code})',
        e,
        st,
      );
      state = ResetPasswordState.error(
        message: AuthErrorMapper.fromException(e),
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue resetPassword', e, st);
      state = const ResetPasswordState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }
}

final resetPasswordControllerProvider =
    StateNotifierProvider<ResetPasswordController, ResetPasswordState>((ref) {
      return ResetPasswordController(ref.read(authRepositoryProvider));
    });

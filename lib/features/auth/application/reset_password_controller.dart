import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/password_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/reset_password_state.dart';

final _log = Logger('ResetPasswordController');

class ResetPasswordController extends StateNotifier<ResetPasswordState> {
  ResetPasswordController(this._repository)
    : super(const ResetPasswordState.idle());

  final AuthRepository _repository;

  Future<void> updatePassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
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
      await _repository.updatePassword(newPassword);
      state = const ResetPasswordState.success();
      _log.info('Mot de passe mis à jour');
    } on AuthException catch (e, st) {
      _log.warning('AuthException resetPassword', e, st);
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

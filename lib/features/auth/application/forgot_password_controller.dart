import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/email_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/forgot_password_state.dart';

final _log = Logger('ForgotPasswordController');

class ForgotPasswordController extends StateNotifier<ForgotPasswordState> {
  ForgotPasswordController(this._repository)
    : super(const ForgotPasswordState.idle());

  final AuthRepository _repository;

  Future<void> sendResetEmail(String email) async {
    if (!EmailValidator.isValid(email)) {
      state = const ForgotPasswordState.error(
        message: 'Adresse email invalide',
      );
      return;
    }

    state = const ForgotPasswordState.submitting();
    try {
      await _repository.sendPasswordResetEmail(email.trim());
      state = const ForgotPasswordState.emailSent();
      _log.info('Email de réinitialisation envoyé');
    } on AuthException catch (e, st) {
      _log.warning('AuthException forgotPassword', e, st);
      // OWASP: éviter énumération users — on affiche toujours emailSent sauf
      // pour rate limit (l'utilisateur a le droit de savoir qu'il envoie trop
      // de requêtes, et ce n'est pas une fuite d'existence de compte).
      final isRateLimit =
          e.code == 'over_email_send_rate_limit' ||
          e.code == 'rate_limit_exceeded' ||
          e.message.toLowerCase().contains('rate limit');
      if (isRateLimit) {
        state = ForgotPasswordState.error(
          message: AuthErrorMapper.fromException(e),
        );
      } else {
        state = const ForgotPasswordState.emailSent();
      }
    } catch (e, st) {
      _log.severe('Erreur inattendue forgotPassword', e, st);
      // OWASP: éviter énumération users — même pour les erreurs inattendues,
      // on affiche emailSent pour ne pas révéler l'existence d'un compte.
      state = const ForgotPasswordState.emailSent();
    }
  }
}

final forgotPasswordControllerProvider =
    StateNotifierProvider<ForgotPasswordController, ForgotPasswordState>((ref) {
      return ForgotPasswordController(ref.read(authRepositoryProvider));
    });

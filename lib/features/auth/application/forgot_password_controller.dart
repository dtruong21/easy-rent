import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/email_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/auth_error.dart';
import '../domain/forgot_password_state.dart';

final _log = Logger('ForgotPasswordController');

class ForgotPasswordController extends StateNotifier<ForgotPasswordState> {
  ForgotPasswordController(this._repository)
    : super(const ForgotPasswordState.idle());

  final AuthRepository _repository;

  Future<void> sendResetEmail(String email) async {
    if (!EmailValidator.isValid(email)) {
      state = ForgotPasswordState.error(
        message: AuthError.invalidEmailFormat.name,
      );
      return;
    }

    state = const ForgotPasswordState.submitting();
    try {
      await _repository.sendPasswordResetEmail(email.trim());
      state = const ForgotPasswordState.emailSent();
      _log.info('Email de réinitialisation envoyé');
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException forgotPassword (code=${e.code})',
        e,
        st,
      );
      // OWASP: éviter énumération users — on affiche emailSent sauf pour
      // rate limit (utilisateur a le droit de savoir qu'il sature, ce n'est
      // pas une fuite d'existence de compte).
      if (e.code == 'too-many-requests') {
        state = ForgotPasswordState.error(
          message: AuthErrorMapper.fromException(e).name,
        );
      } else {
        state = const ForgotPasswordState.emailSent();
      }
    } catch (e, st) {
      _log.severe('Erreur inattendue forgotPassword', e, st);
      // OWASP: éviter énumération users — emailSent même sur erreur inattendue.
      state = const ForgotPasswordState.emailSent();
    }
  }
}

final forgotPasswordControllerProvider =
    StateNotifierProvider<ForgotPasswordController, ForgotPasswordState>((ref) {
      return ForgotPasswordController(ref.read(authRepositoryProvider));
    });

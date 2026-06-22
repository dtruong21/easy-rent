import 'package:freezed_annotation/freezed_annotation.dart';

part 'forgot_password_state.freezed.dart';

/// État UI de la page de demande de réinitialisation de mot de passe.
@freezed
sealed class ForgotPasswordState with _$ForgotPasswordState {
  const factory ForgotPasswordState.idle() = _Idle;
  const factory ForgotPasswordState.submitting() = _Submitting;
  const factory ForgotPasswordState.emailSent() = _EmailSent;
  const factory ForgotPasswordState.error({required String message}) = _Error;
}

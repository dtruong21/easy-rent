import 'package:freezed_annotation/freezed_annotation.dart';

part 'reset_password_state.freezed.dart';

/// État UI de la page de réinitialisation du mot de passe.
///
/// [success] : mot de passe mis à jour, le widget redirige vers /login.
@freezed
sealed class ResetPasswordState with _$ResetPasswordState {
  const factory ResetPasswordState.idle() = _Idle;
  const factory ResetPasswordState.submitting() = _Submitting;
  const factory ResetPasswordState.success() = _Success;
  const factory ResetPasswordState.error({required String message}) = _Error;
}

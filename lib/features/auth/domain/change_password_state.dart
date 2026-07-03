import 'package:freezed_annotation/freezed_annotation.dart';

part 'change_password_state.freezed.dart';

/// État UI de la section « Sécurité » du profil (changement de mot de
/// passe in-app, FEAT-025).
///
/// [success] : mot de passe mis à jour, la session courante est conservée
/// (contrairement à un flow email, l'utilisateur n'est jamais déconnecté).
@freezed
sealed class ChangePasswordState with _$ChangePasswordState {
  const factory ChangePasswordState.idle() = _Idle;
  const factory ChangePasswordState.submitting() = _Submitting;
  const factory ChangePasswordState.success() = _Success;
  const factory ChangePasswordState.error({required String message}) = _Error;
}

import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_page_state.freezed.dart';

/// État UI de la page de connexion email/mot de passe.
@freezed
sealed class LoginPageState with _$LoginPageState {
  const factory LoginPageState.idle() = _Idle;
  const factory LoginPageState.submitting() = _Submitting;
  const factory LoginPageState.error({required String message}) = _Error;
}

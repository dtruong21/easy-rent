import 'package:freezed_annotation/freezed_annotation.dart';

part 'signup_page_state.freezed.dart';

/// État UI de la page de création de compte.
///
/// [awaitingConfirmation] : signup réussi, email de confirmation envoyé.
@freezed
sealed class SignupPageState with _$SignupPageState {
  const factory SignupPageState.idle() = _Idle;
  const factory SignupPageState.submitting() = _Submitting;
  const factory SignupPageState.awaitingConfirmation() = _AwaitingConfirmation;

  /// [ctaRoute] / [ctaLabel] : action de rebond optionnelle affichée sous le
  /// message d'erreur (ex. "Se connecter" → /login quand le compte Google
  /// existe déjà via email/mot de passe).
  const factory SignupPageState.error({
    required String message,
    String? ctaRoute,
    String? ctaLabel,
  }) = _Error;
}

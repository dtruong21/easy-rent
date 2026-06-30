import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_page_state.freezed.dart';

/// État UI de la page de connexion email/mot de passe.
@freezed
sealed class LoginPageState with _$LoginPageState {
  const factory LoginPageState.idle() = _Idle;
  const factory LoginPageState.submitting() = _Submitting;

  /// [ctaRoute] / [ctaLabel] : action de rebond optionnelle affichée sous le
  /// message d'erreur (ex. "Créer un compte" → /signup quand un Google
  /// inconnu de Baillan tente de se connecter).
  const factory LoginPageState.error({
    required String message,
    String? ctaRoute,
    String? ctaLabel,
  }) = _Error;
}

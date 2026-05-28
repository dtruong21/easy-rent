import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_form_state.freezed.dart';

/// État UI du formulaire de connexion.
///
/// Distinct de la session Supabase ([AuthState]) : décrit ce que l'utilisateur
/// voit (formulaire vide, envoi en cours, lien envoyé, erreur).
@freezed
sealed class LoginFormState with _$LoginFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory LoginFormState.idle() = _Idle;

  /// Appel Supabase en cours — bouton désactivé, indicateur affiché.
  const factory LoginFormState.submitting() = _Submitting;

  /// Magic link envoyé avec succès — afficher l'écran de confirmation.
  const factory LoginFormState.linkSent({required String email}) = _LinkSent;

  /// Erreur retournée par Supabase ou validation échouée.
  const factory LoginFormState.error({required String message}) = _Error;
}

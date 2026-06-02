import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_form_state.freezed.dart';

/// État UI du formulaire de profil bailleur.
///
/// Conventions identiques aux autres formulaires du projet :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Supabase en cours, bouton désactivé.
/// - [success] : mise à jour réussie.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class ProfileFormState with _$ProfileFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory ProfileFormState.idle() = _Idle;

  /// Appel Supabase en cours — bouton désactivé, indicateur affiché.
  const factory ProfileFormState.submitting() = _Submitting;

  /// Mise à jour réussie.
  const factory ProfileFormState.success() = _Success;

  /// Erreur retournée par Supabase ou validation échouée.
  const factory ProfileFormState.error({required String message}) = _Error;
}

import 'package:freezed_annotation/freezed_annotation.dart';

import 'property.dart';

part 'property_form_state.freezed.dart';

/// État UI du formulaire bien immobilier.
///
/// Mêmes conventions que [LoginFormState] :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Firestore en cours, bouton désactivé.
/// - [success] : opération réussie, contient le bien créé/mis à jour.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class PropertyFormState with _$PropertyFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory PropertyFormState.idle() = _Idle;

  /// Appel Firestore en cours — bouton désactivé, indicateur affiché.
  const factory PropertyFormState.submitting() = _Submitting;

  /// Opération réussie — contient le bien créé ou mis à jour.
  const factory PropertyFormState.success({required Property property}) =
      _Success;

  /// Erreur retournée par Firestore ou validation échouée.
  const factory PropertyFormState.error({required String message}) = _Error;
}

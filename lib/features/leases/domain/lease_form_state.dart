import 'package:freezed_annotation/freezed_annotation.dart';

import 'lease.dart';

part 'lease_form_state.freezed.dart';

/// État UI du formulaire bail.
///
/// Mêmes conventions que [TenantFormState] et [PropertyFormState] :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Supabase en cours, bouton désactivé.
/// - [success] : opération réussie, contient le bail créé/mis à jour.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class LeaseFormState with _$LeaseFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory LeaseFormState.idle() = _Idle;

  /// Appel Supabase en cours — bouton désactivé, indicateur affiché.
  const factory LeaseFormState.submitting() = _Submitting;

  /// Opération réussie — contient le bail créé ou mis à jour.
  const factory LeaseFormState.success({required Lease lease}) = _Success;

  /// Erreur retournée par Supabase ou validation échouée.
  const factory LeaseFormState.error({required String message}) = _Error;
}

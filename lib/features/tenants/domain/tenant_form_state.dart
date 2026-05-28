import 'package:freezed_annotation/freezed_annotation.dart';

import 'tenant.dart';

part 'tenant_form_state.freezed.dart';

/// État UI du formulaire locataire.
///
/// Mêmes conventions que [PropertyFormState] et [LoginFormState] :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Supabase en cours, bouton désactivé.
/// - [success] : opération réussie, contient le locataire créé/mis à jour.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class TenantFormState with _$TenantFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory TenantFormState.idle() = _Idle;

  /// Appel Supabase en cours — bouton désactivé, indicateur affiché.
  const factory TenantFormState.submitting() = _Submitting;

  /// Opération réussie — contient le locataire créé ou mis à jour.
  const factory TenantFormState.success({required Tenant tenant}) = _Success;

  /// Erreur retournée par Supabase ou validation échouée.
  const factory TenantFormState.error({required String message}) = _Error;
}

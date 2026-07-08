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

  /// Erreur retournée par le backend ou validation échouée.
  ///
  /// [message] porte une **clé technique stable** (`TenantSubmitError.name`,
  /// voir `../domain/tenant_submit_error.dart`), pas un texte FR en dur —
  /// FEAT-043 (i18n). La couche présentation reconvertit via
  /// `TenantSubmitError.fromCode(message).message(context)`
  /// (`../presentation/tenant_submit_error_l10n.dart`). Champ resté `String`
  /// (et non l'enum directement) car `TenantFormState` est généré par
  /// `freezed`/`build_runner`, non ré-exécutable dans cet environnement —
  /// voir le commentaire de tête de `tenant_submit_error.dart`.
  const factory TenantFormState.error({required String message}) = _Error;
}

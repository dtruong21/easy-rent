import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_form_state.freezed.dart';

/// Motif d'échec de soumission du formulaire profil — indépendant de la
/// locale d'affichage (FEAT-043).
///
/// [ProfileFormController] (application, sans `BuildContext`) reste une
/// fonction pure : il détermine le motif mais ne compose aucun message
/// traduit. La couche présentation ([ProfileDetailsPage]) mappe cet enum
/// vers `context.l10n.<clé>` via l'extension `ProfileFormErrorReasonL10n`
/// (voir `lib/features/profile/presentation/profile_form_error_reason_l10n.dart`).
enum ProfileFormErrorReason {
  /// Erreur réseau/backend (ex. `FirebaseException`) lors de la sauvegarde.
  saveFailed,

  /// Profil introuvable (session invalide ou document supprimé).
  profileNotFound,

  /// Erreur inattendue non catégorisée.
  unexpected,
}

/// État UI du formulaire de profil bailleur.
///
/// Conventions identiques aux autres formulaires du projet :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Supabase en cours, bouton désactivé.
/// - [success] : mise à jour réussie.
/// - [error] : échec ; [ProfileFormErrorReason] traduit en présentation.
@freezed
sealed class ProfileFormState with _$ProfileFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory ProfileFormState.idle() = _Idle;

  /// Appel Supabase en cours — bouton désactivé, indicateur affiché.
  const factory ProfileFormState.submitting() = _Submitting;

  /// Mise à jour réussie.
  const factory ProfileFormState.success() = _Success;

  /// Erreur retournée par Supabase ou validation échouée.
  const factory ProfileFormState.error({
    required ProfileFormErrorReason reason,
  }) = _Error;
}

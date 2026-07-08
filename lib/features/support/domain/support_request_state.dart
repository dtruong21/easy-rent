import 'package:freezed_annotation/freezed_annotation.dart';

part 'support_request_state.freezed.dart';

/// État UI du formulaire « Nous contacter » (`/profile`, section Support,
/// FEAT-025).
///
/// [success] : la demande a été écrite dans `support_requests` — le
/// formulaire est write-only, aucune relecture côté client.
@freezed
sealed class SupportRequestState with _$SupportRequestState {
  const factory SupportRequestState.idle() = _Idle;
  const factory SupportRequestState.submitting() = _Submitting;
  const factory SupportRequestState.success() = _Success;

  /// Erreur de validation locale ou d'envoi.
  ///
  /// [message] porte une **clé technique stable** (`SupportSubmitError.name`,
  /// voir `../domain/support_submit_error.dart`), pas un texte FR en dur —
  /// FEAT-043 (i18n). La couche présentation reconvertit via
  /// `SupportSubmitError.fromCode(message).message(context)`
  /// (`../presentation/support_submit_error_l10n.dart`). Champ resté
  /// `String` (et non l'enum directement) car `SupportRequestState` est
  /// généré par `freezed`/`build_runner`, non ré-exécutable dans cet
  /// environnement — voir le commentaire de tête de
  /// `support_submit_error.dart`.
  const factory SupportRequestState.error({required String message}) = _Error;
}

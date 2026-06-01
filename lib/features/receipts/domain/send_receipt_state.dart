import 'package:freezed_annotation/freezed_annotation.dart';

part 'send_receipt_state.freezed.dart';

/// État UI du flow d'envoi d'une quittance par email.
///
/// - [idle] : bouton au repos.
/// - [submitting] : appel Edge Function en cours, bouton désactivé.
/// - [confirmingResend] : quittance déjà envoyée — dialog de confirmation
///   en attente de décision utilisateur.
/// - [success] : email envoyé — [sentAt] et [sentToEmail] mis à jour.
/// - [error] : échec générique, message FR affiché via SnackBar.
/// - [tenantNoEmail] : 422 tenant_no_email — locataire sans email.
/// - [rateLimited] : 429 quota_exceeded — quota Resend dépassé.
@freezed
sealed class SendReceiptState with _$SendReceiptState {
  /// Bouton au repos — prêt à déclencher l'envoi.
  const factory SendReceiptState.idle() = SendReceiptIdle;

  /// Appel en cours — bouton désactivé, indicateur affiché.
  const factory SendReceiptState.submitting() = SendReceiptSubmitting;

  /// Quittance déjà envoyée — attend confirmation de renvoi.
  ///
  /// [previousSentAt] : date du dernier envoi (pour affichage dans le dialog).
  /// [previousMaskedEmail] : email masqué RGPD du dernier envoi.
  const factory SendReceiptState.confirmingResend({
    required DateTime previousSentAt,
    required String previousMaskedEmail,
  }) = SendReceiptConfirmingResend;

  /// Envoi réussi — [sentAt] et [sentToEmail] sont les nouvelles valeurs.
  const factory SendReceiptState.success({
    required DateTime sentAt,
    required String sentToEmail,
  }) = SendReceiptSuccess;

  /// Erreur générique — [message] est affiché dans un SnackBar.
  const factory SendReceiptState.error({required String message}) =
      SendReceiptError;

  /// Locataire sans adresse email (422 tenant_no_email).
  ///
  /// L'UI affiche un SnackBar avec action "Modifier la fiche locataire".
  const factory SendReceiptState.tenantNoEmail() = SendReceiptTenantNoEmail;

  /// Quota Resend dépassé (429 quota_exceeded).
  const factory SendReceiptState.rateLimited() = SendReceiptRateLimited;
}

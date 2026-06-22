import 'package:freezed_annotation/freezed_annotation.dart';

part 'share_receipt_state.freezed.dart';

/// État UI du flow de partage d'une quittance (Web Share API + fallback mailto:).
///
/// - [idle] : bouton au repos.
/// - [preparing] : récupération du PDF et vérification du support, bouton désactivé.
/// - [confirmingResend] : quittance déjà partagée — dialog de confirmation
///   en attente de décision utilisateur.
/// - [shared] : partage réussi — [sharedAt], [sharedToEmail] et [usedNativeShare]
///   sont renseignés.
/// - [tenantNoEmail] : locataire sans adresse email, bouton désactivé.
/// - [error] : échec générique, [message] affiché via SnackBar.
@freezed
sealed class ShareReceiptState with _$ShareReceiptState {
  /// Bouton au repos — prêt à déclencher le partage.
  const factory ShareReceiptState.idle() = ShareReceiptIdle;

  /// Préparation en cours — récupération PDF et vérification du support.
  const factory ShareReceiptState.preparing() = ShareReceiptPreparing;

  /// Quittance déjà partagée — attend confirmation de renvoi.
  ///
  /// [previousSharedAt] : date du dernier partage (pour affichage dans le dialog).
  /// [previousMaskedEmail] : email masqué RGPD du dernier partage.
  const factory ShareReceiptState.confirmingResend({
    required DateTime previousSharedAt,
    required String previousMaskedEmail,
  }) = ShareReceiptConfirmingResend;

  /// Partage réussi.
  ///
  /// [sharedAt] et [sharedToEmail] proviennent de la DB après `markReceiptAsShared`.
  /// [usedNativeShare] : true si la Web Share API a été utilisée,
  /// false si le fallback download+mailto a été employé.
  const factory ShareReceiptState.shared({
    required DateTime sharedAt,
    required String sharedToEmail,
    required bool usedNativeShare,
  }) = ShareReceiptShared;

  /// Locataire sans adresse email — partage impossible, bouton désactivé.
  const factory ShareReceiptState.tenantNoEmail() = ShareReceiptTenantNoEmail;

  /// Erreur générique — [message] affiché dans un SnackBar.
  const factory ShareReceiptState.error({required String message}) =
      ShareReceiptError;
}

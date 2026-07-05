import 'package:freezed_annotation/freezed_annotation.dart';

part 'charge_regularization_share_state.freezed.dart';

/// État UI du flow de génération + partage de l'avis de régularisation
/// (FEAT-029 V1.2).
///
/// Plus simple que `ShareReceiptState` (receipts) : pas de doc Firestore à
/// marquer "envoyé" après partage — le PDF est généré à la volée et
/// directement partagé, sans persistance (V1, cf. backlog FEAT-029 §
/// « Out of scope » — pas d'archivage automatique en `documents`).
@freezed
sealed class ChargeRegularizationShareState
    with _$ChargeRegularizationShareState {
  /// État initial — formulaire prêt.
  const factory ChargeRegularizationShareState.idle() =
      ChargeRegularizationShareIdle;

  /// Génération PDF + partage en cours.
  const factory ChargeRegularizationShareState.preparing() =
      ChargeRegularizationSharePreparing;

  /// Partage réussi — [usedNativeShare] indique Web Share API vs fallback
  /// téléchargement + mailto:.
  const factory ChargeRegularizationShareState.shared({
    required bool usedNativeShare,
  }) = ChargeRegularizationShareShared;

  /// Erreur lors de la génération ou du partage.
  const factory ChargeRegularizationShareState.error({
    required String message,
  }) = ChargeRegularizationShareError;
}

import 'package:freezed_annotation/freezed_annotation.dart';

import 'receipt_generation_result.dart';

part 'receipt_generation_state.freezed.dart';

/// État UI du flow de génération d'une quittance.
///
/// - [idle] : bouton prêt à l'action.
/// - [submitting] : appel Edge Function en cours, bouton désactivé.
/// - [success] : quittance générée — contient le résultat + URL signée.
/// - [error] : échec, message en français affiché via SnackBar.
/// - [profileIncomplete] : Edge Function a retourné 422 `profile_incomplete`.
///   L'UI doit afficher [ProfileIncompleteDialog] avec la liste des champs manquants.
@freezed
sealed class ReceiptGenerationState with _$ReceiptGenerationState {
  /// Bouton au repos — prêt à déclencher la génération.
  const factory ReceiptGenerationState.idle() = _Idle;

  /// Appel en cours — bouton désactivé, indicateur affiché.
  const factory ReceiptGenerationState.submitting() = _Submitting;

  /// Génération réussie — contient le résultat de la génération.
  const factory ReceiptGenerationState.success({
    required ReceiptGenerationResult result,
  }) = _Success;

  /// Erreur retournée par l'Edge Function ou réseau.
  const factory ReceiptGenerationState.error({required String message}) =
      _Error;

  /// Profil bailleur incomplet — [missing] contient les champs manquants.
  ///
  /// Déclenche [ProfileIncompleteDialog] côté UI.
  const factory ReceiptGenerationState.profileIncomplete({
    required List<String> missing,
  }) = _ProfileIncomplete;
}

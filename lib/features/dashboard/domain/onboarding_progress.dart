import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_progress.freezed.dart';

/// Progression d'onboarding d'un bailleur, dérivée des collections existantes
/// (aucune écriture, aucun champ Firestore dédié).
///
/// [firstLeaseId] : id d'un bail du bailleur (pour router les étapes 4-5,
/// lease-scoped) ; `null` tant qu'aucun bail n'existe.
///
/// [isComplete] : l'onboarding s'achève à la 1re quittance générée
/// (`hasReceipt`) — le moment de valeur (quittance loi 6 juillet 1989).
@freezed
class OnboardingProgress with _$OnboardingProgress {
  const OnboardingProgress._();

  const factory OnboardingProgress({
    required bool hasProperty,
    required bool hasTenant,
    required bool hasLease,
    required bool hasPayment,
    required bool hasReceipt,
    required String? firstLeaseId,
  }) = _OnboardingProgress;

  bool get isComplete => hasReceipt;

  int get completedCount => [
    hasProperty,
    hasTenant,
    hasLease,
    hasPayment,
    hasReceipt,
  ].where((e) => e).length;
}

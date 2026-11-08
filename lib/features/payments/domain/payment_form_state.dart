import 'package:freezed_annotation/freezed_annotation.dart';

import 'payment.dart';

part 'payment_form_state.freezed.dart';

/// État UI du formulaire paiement.
///
/// Mêmes conventions que [LeaseFormState] :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Firestore en cours, bouton désactivé.
/// - [success] : opération réussie, contient le paiement créé/mis à jour.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class PaymentFormState with _$PaymentFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory PaymentFormState.idle() = _Idle;

  /// Appel Firestore en cours — bouton désactivé, indicateur affiché.
  const factory PaymentFormState.submitting() = _Submitting;

  /// Opération réussie — contient le paiement créé ou mis à jour.
  const factory PaymentFormState.success({required Payment payment}) = _Success;

  /// Erreur retournée par Firestore ou validation échouée.
  const factory PaymentFormState.error({required String message}) = _Error;
}

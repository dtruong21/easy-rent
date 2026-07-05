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
  const factory SupportRequestState.error({required String message}) = _Error;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/support_repository.dart';
import '../domain/support_request_state.dart';
import '../domain/support_submit_error.dart';

final _log = Logger('FeedbackController');

/// Contrôle le formulaire « Donner mon avis » (FEAT-060). Même état que
/// « Nous contacter » ([SupportRequestState]) ; validation bornée sur les
/// mêmes valeurs que les rules `support_requests` (branche avis).
class FeedbackController extends StateNotifier<SupportRequestState> {
  FeedbackController(this._repository)
    : super(const SupportRequestState.idle());

  final SupportRepository _repository;

  Future<void> submit({
    required int? rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    if (rating == null ||
        rating < kFeedbackRatingMin ||
        rating > kFeedbackRatingMax) {
      state = SupportRequestState.error(
        message: SupportSubmitError.ratingRequired.name,
      );
      return;
    }
    final trimmed = comment.trim();
    if (trimmed.length > kSupportMessageMaxLength) {
      state = SupportRequestState.error(
        message: SupportSubmitError.messageTooLong.name,
      );
      return;
    }

    state = const SupportRequestState.submitting();
    try {
      await _repository.submitFeedback(
        rating: rating,
        comment: trimmed,
        appVersion: appVersion,
        appEnv: appEnv,
        platform: platform,
      );
      state = const SupportRequestState.success();
      _log.info('Avis envoyé');
    } catch (e, st) {
      _log.warning('Erreur envoi avis', e, st);
      state = SupportRequestState.error(
        message: SupportSubmitError.sendFailed.name,
      );
    }
  }

  void reset() => state = const SupportRequestState.idle();
}

final feedbackControllerProvider =
    StateNotifierProvider.autoDispose<FeedbackController, SupportRequestState>(
      (ref) => FeedbackController(ref.watch(supportRepositoryProvider)),
    );

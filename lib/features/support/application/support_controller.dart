import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/support_repository.dart';
import '../domain/support_request_state.dart';
import '../domain/support_submit_error.dart';

final _log = Logger('SupportController');

/// Contrôle le formulaire « Nous contacter » (`ProfileSupportSection`,
/// FEAT-025).
///
/// Validation locale bornée sur les mêmes tailles que les rules Firestore
/// (`support_requests` create-only) — un rejet côté rules ne devrait donc
/// jamais se produire en usage normal, mais reste possible si les deux
/// bornes divergent un jour (defense in depth).
///
/// Pas d'anti-énumération OWASP : ce flow est write-only, sans information
/// sensible retournée à l'appelant.
class SupportController extends StateNotifier<SupportRequestState> {
  SupportController(this._repository) : super(const SupportRequestState.idle());

  final SupportRepository _repository;

  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {
    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();

    if (trimmedSubject.isEmpty) {
      state = SupportRequestState.error(
        message: SupportSubmitError.subjectRequired.name,
      );
      return;
    }
    if (trimmedSubject.length > kSupportSubjectMaxLength) {
      state = SupportRequestState.error(
        message: SupportSubmitError.subjectTooLong.name,
      );
      return;
    }
    if (trimmedMessage.isEmpty) {
      state = SupportRequestState.error(
        message: SupportSubmitError.messageRequired.name,
      );
      return;
    }
    if (trimmedMessage.length > kSupportMessageMaxLength) {
      state = SupportRequestState.error(
        message: SupportSubmitError.messageTooLong.name,
      );
      return;
    }

    state = const SupportRequestState.submitting();
    try {
      await _repository.submit(
        subject: trimmedSubject,
        message: trimmedMessage,
        appVersion: appVersion,
        appEnv: appEnv,
      );
      state = const SupportRequestState.success();
      _log.info('Demande de support envoyée');
    } catch (e, st) {
      _log.warning('Erreur envoi demande de support', e, st);
      state = SupportRequestState.error(
        message: SupportSubmitError.sendFailed.name,
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après un succès affiché
  /// via SnackBar, pour éviter qu'un re-listen retriggère l'affichage).
  void reset() => state = const SupportRequestState.idle();
}

final supportControllerProvider =
    StateNotifierProvider.autoDispose<SupportController, SupportRequestState>(
      (ref) => SupportController(ref.read(supportRepositoryProvider)),
    );

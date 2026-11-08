import 'package:easyrent/features/support/application/feedback_controller.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/domain/support_request_state.dart';
import 'package:easyrent/features/support/domain/support_submit_error.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements SupportRepository {
  final List<Map<String, Object>> feedbacks = [];
  Object? error;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {}

  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    if (error != null) throw error!;
    feedbacks.add({'rating': rating, 'comment': comment, 'platform': platform});
  }
}

void main() {
  late _FakeRepo repo;
  late FeedbackController controller;
  setUp(() {
    repo = _FakeRepo();
    controller = FeedbackController(repo);
  });
  tearDown(() => controller.dispose());

  Future<void> send({int? rating = 4, String comment = '  Super  '}) =>
      controller.submit(
        rating: rating,
        comment: comment,
        appVersion: '1.0.0+1',
        appEnv: 'dev',
        platform: 'ios',
      );

  test('note absente → erreur ratingRequired, rien envoyé', () async {
    await send(rating: null);
    expect(
      controller.state,
      SupportRequestState.error(
        message: SupportSubmitError.ratingRequired.name,
      ),
    );
    expect(repo.feedbacks, isEmpty);
  });

  test('note hors 1-5 → erreur ratingRequired', () async {
    await send(rating: 0);
    await send(rating: 6);
    expect(repo.feedbacks, isEmpty);
  });

  test('commentaire > 2000 → erreur messageTooLong', () async {
    await send(comment: 'x' * 2001);
    expect(
      controller.state,
      SupportRequestState.error(
        message: SupportSubmitError.messageTooLong.name,
      ),
    );
  });

  test('avis valide → envoyé (commentaire nettoyé), succès', () async {
    await send();
    expect(repo.feedbacks.single, {
      'rating': 4,
      'comment': 'Super',
      'platform': 'ios',
    });
    expect(controller.state, const SupportRequestState.success());
  });

  test('commentaire vide autorisé', () async {
    await send(comment: '   ');
    expect(repo.feedbacks.single['comment'], '');
  });

  test('échec du dépôt → erreur sendFailed', () async {
    repo.error = StateError('réseau');
    await send();
    expect(
      controller.state,
      SupportRequestState.error(message: SupportSubmitError.sendFailed.name),
    );
  });
}

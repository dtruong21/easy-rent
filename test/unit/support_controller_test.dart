import 'package:easyrent/features/support/application/support_controller.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/domain/support_request_state.dart';
import 'package:easyrent/features/support/domain/support_submit_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeSupportRepository implements SupportRepository {
  bool submitCalled = false;
  String? lastSubject;
  String? lastMessage;
  String? lastAppVersion;
  String? lastAppEnv;
  Exception? submitError;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {
    submitCalled = true;
    lastSubject = subject;
    lastMessage = message;
    lastAppVersion = appVersion;
    lastAppEnv = appEnv;
    final err = submitError;
    if (err != null) throw err;
  }
}

SupportController _makeController(_FakeSupportRepository repo) {
  final container = ProviderContainer(
    overrides: [supportRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(supportControllerProvider.notifier);
}

bool _isError(SupportRequestState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isSuccess(SupportRequestState s) =>
    s.maybeWhen(success: () => true, orElse: () => false);

String _errorMsg(SupportRequestState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

const _validSubject = 'Problème de quittance';
const _validMessage = 'La quittance de mars ne se génère pas.';

void main() {
  group('SupportController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeSupportRepository());
      expect(ctrl.state, const SupportRequestState.idle());
    });

    group('submit — chemin nominal', () {
      test('transitions idle → submitting → success', () async {
        final repo = _FakeSupportRepository();
        final container = ProviderContainer(
          overrides: [supportRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <SupportRequestState>[];
        container.listen<SupportRequestState>(
          supportControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(supportControllerProvider.notifier)
            .submit(
              subject: _validSubject,
              message: _validMessage,
              appVersion: '1.0.0+42',
              appEnv: 'dev',
            );

        expect(states[0], const SupportRequestState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isSuccess(states[2]), isTrue);
        expect(repo.submitCalled, isTrue);
        expect(repo.lastSubject, _validSubject);
        expect(repo.lastMessage, _validMessage);
        expect(repo.lastAppVersion, '1.0.0+42');
        expect(repo.lastAppEnv, 'dev');
      });

      test('trim() appliqué au sujet et au message avant envoi', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: '  $_validSubject  ',
          message: '  $_validMessage  ',
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.lastSubject, _validSubject);
        expect(repo.lastMessage, _validMessage);
      });
    });

    group('submit — validation locale', () {
      test('sujet vide → error sans appel repo', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: '',
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), SupportSubmitError.subjectRequired.name);
      });

      test('sujet uniquement des espaces → traité comme vide', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: '   ',
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isFalse);
        expect(_errorMsg(ctrl.state), SupportSubmitError.subjectRequired.name);
      });

      test('sujet > 120 caractères → error sans appel repo', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: 'a' * 121,
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isFalse);
        expect(_errorMsg(ctrl.state), SupportSubmitError.subjectTooLong.name);
      });

      test('sujet exactement 120 caractères → accepté', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: 'a' * 120,
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isTrue);
        expect(_isSuccess(ctrl.state), isTrue);
      });

      test('message vide → error sans appel repo', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: _validSubject,
          message: '',
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isFalse);
        expect(_errorMsg(ctrl.state), SupportSubmitError.messageRequired.name);
      });

      test('message > 2000 caractères → error sans appel repo', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: _validSubject,
          message: 'a' * 2001,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isFalse);
        expect(_errorMsg(ctrl.state), SupportSubmitError.messageTooLong.name);
      });

      test('message exactement 2000 caractères → accepté', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: _validSubject,
          message: 'a' * 2000,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(repo.submitCalled, isTrue);
        expect(_isSuccess(ctrl.state), isTrue);
      });
    });

    group('submit — erreurs', () {
      test('exception du repo → message générique retentable', () async {
        final repo = _FakeSupportRepository()
          ..submitError = Exception('network down');
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: _validSubject,
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), SupportSubmitError.sendFailed.name);
      });
    });

    group('reset', () {
      test('reset() remet l\'état à idle après un succès', () async {
        final repo = _FakeSupportRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          subject: _validSubject,
          message: _validMessage,
          appVersion: '1.0.0+42',
          appEnv: 'dev',
        );
        expect(_isSuccess(ctrl.state), isTrue);

        ctrl.reset();
        expect(ctrl.state, const SupportRequestState.idle());
      });
    });
  });
}

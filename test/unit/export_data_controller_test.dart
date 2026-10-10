import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/account/application/export_data_controller.dart';
import 'package:easyrent/features/account/data/account_export_repository.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// RGPD export (Task 4) — le contrôleur orchestre callable → sérialisation
// JSON → remise du fichier via WebShareService. Voir aussi
// `.superpowers/sdd/2026-09-11-rgpd-data-export/task-4-brief.md`.
// ---------------------------------------------------------------------------

class _FakeAccountExportRepository implements AccountExportRepository {
  Object? errorToThrow;
  Map<String, dynamic> dataToReturn = const {'foo': 'bar'};

  @override
  Future<Map<String, dynamic>> exportAccountData() async {
    if (errorToThrow != null) throw errorToThrow!;
    return dataToReturn;
  }
}

class _FakeWebShareService implements WebShareService {
  final List<Map<String, Object?>> deliverFileCalls = [];

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {
    deliverFileCalls.add({
      'filename': filename,
      'mimeType': mimeType,
      'bytes': bytes,
      'shareTitle': shareTitle,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

({
  ProviderContainer container,
  _FakeAccountExportRepository repo,
  _FakeWebShareService share,
})
_make() {
  final repo = _FakeAccountExportRepository();
  final share = _FakeWebShareService();
  final container = ProviderContainer(
    overrides: [
      accountExportRepositoryProvider.overrideWithValue(repo),
      webShareServiceProvider.overrideWithValue(share),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo, share: share);
}

void main() {
  test(
    'export() succès : loading -> success, deliverFile appelé avec le JSON exporté',
    () async {
      final (:container, :repo, :share) = _make();
      repo.dataToReturn = {
        'landlord': {'fullName': 'Alice Dupont'},
        'leases': [1, 2, 3],
      };
      final controller = container.read(exportDataControllerProvider.notifier);

      final future = controller.export();
      // L'appel est synchrone jusqu'au premier `await` — l'état loading doit
      // déjà être visible avant que la Future ne se résolve.
      expect(
        container.read(exportDataControllerProvider).status,
        ExportDataStatus.loading,
      );

      await future;

      final state = container.read(exportDataControllerProvider);
      expect(state.status, ExportDataStatus.success);
      expect(state.errorKind, ExportDataErrorKind.none);

      expect(share.deliverFileCalls, hasLength(1));
      final call = share.deliverFileCalls.single;
      final filename = call['filename'] as String;
      expect(filename, startsWith('baillan-export-'));
      expect(filename, endsWith('.json'));
      expect(call['mimeType'], 'application/json');

      final bytes = call['bytes'] as List<int>;
      final decoded = jsonDecode(utf8.decode(bytes));
      expect(decoded, repo.dataToReturn);
    },
  );

  test(
    'export() erreur générique : repo throw -> status error, errorKind generic',
    () async {
      final (:container, :repo, :share) = _make();
      repo.errorToThrow = Exception('boom');
      final controller = container.read(exportDataControllerProvider.notifier);

      await controller.export();

      final state = container.read(exportDataControllerProvider);
      expect(state.status, ExportDataStatus.error);
      expect(state.errorKind, ExportDataErrorKind.generic);
      expect(share.deliverFileCalls, isEmpty);
    },
  );

  test(
    'export() recent-login-required : errorKind dédié, pas de deliverFile',
    () async {
      final (:container, :repo, :share) = _make();
      repo.errorToThrow = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'recent-login-required',
      );
      final controller = container.read(exportDataControllerProvider.notifier);

      await controller.export();

      final state = container.read(exportDataControllerProvider);
      expect(state.status, ExportDataStatus.error);
      expect(state.errorKind, ExportDataErrorKind.recentLoginRequired);
      expect(share.deliverFileCalls, isEmpty);
    },
  );
}

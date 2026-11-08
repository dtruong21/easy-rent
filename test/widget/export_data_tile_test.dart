import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/account/data/account_export_repository.dart';
import 'package:easyrent/features/account/presentation/widgets/export_data_tile.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// RGPD export (Task 5) — ExportDataTile consomme exportDataControllerProvider
// (Task 4). On teste via de vrais fakes repo/share (comme
// export_data_controller_test.dart) plutôt qu'en overridant directement le
// contrôleur : ça exerce le vrai enchaînement idle -> loading -> success/error
// et les SnackBars affichés par la tuile.
// Voir aussi .superpowers/sdd/2026-09-11-rgpd-data-export/task-5-brief.md.
// ---------------------------------------------------------------------------

class _FakeAccountExportRepository implements AccountExportRepository {
  Object? errorToThrow;
  Completer<void>? gate;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> exportAccountData() async {
    callCount++;
    if (gate != null) await gate!.future;
    if (errorToThrow != null) throw errorToThrow!;
    return const {'foo': 'bar'};
  }
}

class _FakeWebShareService implements WebShareService {
  final List<String> deliveredFilenames = [];

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {
    deliveredFilenames.add(filename);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _wrap({
  required AccountExportRepository repo,
  required WebShareService share,
}) => ProviderScope(
  overrides: [
    accountExportRepositoryProvider.overrideWithValue(repo),
    webShareServiceProvider.overrideWithValue(share),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const Scaffold(body: ExportDataTile()),
  ),
);

void main() {
  testWidgets('la tuile tile_export_data est présente avec le libellé', (
    tester,
  ) async {
    final repo = _FakeAccountExportRepository();
    final share = _FakeWebShareService();
    await tester.pumpWidget(_wrap(repo: repo, share: share));

    expect(find.byKey(const Key('tile_export_data')), findsOneWidget);
    expect(find.text('Exporter mes données'), findsOneWidget);
  });

  testWidgets('tap sur la tuile appelle export()', (tester) async {
    final repo = _FakeAccountExportRepository();
    final share = _FakeWebShareService();
    await tester.pumpWidget(_wrap(repo: repo, share: share));

    await tester.tap(find.byKey(const Key('tile_export_data')));
    await tester.pumpAndSettle();

    expect(repo.callCount, 1);
    expect(share.deliveredFilenames, hasLength(1));
  });

  testWidgets(
    'pendant le chargement, un indicateur de progression est visible',
    (tester) async {
      final repo = _FakeAccountExportRepository()..gate = Completer<void>();
      final share = _FakeWebShareService();
      await tester.pumpWidget(_wrap(repo: repo, share: share));

      await tester.tap(find.byKey(const Key('tile_export_data')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('après succès, un SnackBar de succès s\'affiche', (tester) async {
    final repo = _FakeAccountExportRepository();
    final share = _FakeWebShareService();
    await tester.pumpWidget(_wrap(repo: repo, share: share));

    await tester.tap(find.byKey(const Key('tile_export_data')));
    await tester.pumpAndSettle();

    expect(find.text('Export prêt'), findsOneWidget);
  });

  testWidgets(
    'après erreur recentLoginRequired, le message de reconnexion s\'affiche',
    (tester) async {
      final repo = _FakeAccountExportRepository()
        ..errorToThrow = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'recent-login-required',
        );
      final share = _FakeWebShareService();
      await tester.pumpWidget(_wrap(repo: repo, share: share));

      await tester.tap(find.byKey(const Key('tile_export_data')));
      await tester.pumpAndSettle();

      expect(
        find.text('Reconnectez-vous, puis réessayez l\'export.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('après erreur générique, un SnackBar d\'erreur s\'affiche', (
    tester,
  ) async {
    final repo = _FakeAccountExportRepository()
      ..errorToThrow = Exception('boom');
    final share = _FakeWebShareService();
    await tester.pumpWidget(_wrap(repo: repo, share: share));

    await tester.tap(find.byKey(const Key('tile_export_data')));
    await tester.pumpAndSettle();

    expect(find.text('L\'export a échoué. Réessayez.'), findsOneWidget);
  });
}

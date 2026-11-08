/// Tests widget de [ReceiptsListSection].
///
/// Couvre : titre, état vide, ligne de synthèse (nombre + dernière période),
/// et la navigation vers l'écran complet des quittances au tap.
///
/// Note (2026-08-11) : la section n'affiche plus la timeline embarquée des
/// 3 dernières quittances (zone jugée trop étroite par le propriétaire) —
/// elle affiche désormais une ligne compacte cliquable qui ouvre
/// `/leases/:id/receipts`. Les anciens tests sur les pills de statut
/// (Payée/Annulée/Périmée) sont retirés d'ici : cette information reste
/// visible, mais uniquement sur la page complète (déjà couverte par les
/// tests de `LeaseReceiptsPage`) — plus dans cette carte embarquée.
library;

import 'dart:typed_data';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/receipts_list_section.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeReceiptsRepo implements ReceiptsRepository {
  final List<Receipt> receipts;
  _FakeReceiptsRepo(this.receipts);

  @override
  Future<List<Receipt>> listForLease(String leaseId) async =>
      receipts.where((r) => r.leaseId == leaseId).toList();

  @override
  Future<Receipt> getById(String id) async => throw UnimplementedError();

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async => throw UnimplementedError();

  @override
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Receipt _makeReceipt({
  required String id,
  DateTime? periodStart,
  bool isVoided = false,
  bool isStale = false,
  DocumentType documentType = DocumentType.quittance,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: const ['pay-1'],
  periodStart: periodStart ?? DateTime(2026, 1, 1),
  periodEnd: (periodStart ?? DateTime(2026, 1, 1)).add(
    const Duration(days: 30),
  ),
  totalCents: 90000,
  rentCents: 85000,
  chargesCents: 5000,
  documentType: documentType,
  pdfPath: 'landlord-1/$id.pdf',
  isVoided: isVoided,
  isStale: isStale,
  generatedAt: DateTime(2026, 2, 1),
  createdAt: DateTime(2026, 2, 1),
);

Widget _buildSection(List<Receipt> receipts) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(
            child: ReceiptsListSection(leaseId: 'lease-1'),
          ),
        ),
      ),
      // Route cible de la ligne de synthèse : écran complet des quittances.
      GoRoute(
        path: '/leases/:id/receipts',
        builder: (context, _) =>
            const Scaffold(body: Text('Toutes les quittances')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      receiptsRepositoryProvider.overrideWithValue(_FakeReceiptsRepo(receipts)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: _appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ReceiptsListSection', () {
    testWidgets('titre "Quittances émises" visible', (tester) async {
      await tester.pumpWidget(_buildSection([]));
      await tester.pumpAndSettle();
      expect(find.text('Quittances émises'), findsOneWidget);
    });

    testWidgets('liste vide → message "Aucune quittance générée."', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection([]));
      await tester.pumpAndSettle();
      expect(find.text('Aucune quittance générée.'), findsOneWidget);
    });

    testWidgets('liste vide → pas de ligne de synthèse cliquable', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection([]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tile_receipts_summary')), findsNothing);
    });

    testWidgets(
      'liste non vide → ligne de synthèse visible avec le nombre de quittances',
      (tester) async {
        final receipts = [_makeReceipt(id: 'r-1'), _makeReceipt(id: 'r-2')];
        await tester.pumpWidget(_buildSection(receipts));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tile_receipts_summary')), findsOneWidget);
        expect(find.text('2 quittances'), findsOneWidget);
      },
    );

    testWidgets('une seule quittance → singulier "1 quittance"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection([_makeReceipt(id: 'r-1')]));
      await tester.pumpAndSettle();
      expect(find.text('1 quittance'), findsOneWidget);
    });

    testWidgets(
      'ligne de synthèse → affiche la période de la quittance la plus '
      'récente (period_start DESC, la 1ère de la liste)',
      (tester) async {
        final receipts = [
          _makeReceipt(id: 'r-recent', periodStart: DateTime(2026, 8, 1)),
          _makeReceipt(id: 'r-old', periodStart: DateTime(2026, 1, 1)),
        ];
        await tester.pumpWidget(_buildSection(receipts));
        await tester.pumpAndSettle();
        expect(find.text('Dernière : Août 2026'), findsOneWidget);
        expect(find.textContaining('Janvier'), findsNothing);
      },
    );

    testWidgets(
      'plusieurs quittances → une seule ligne de synthèse, jamais une liste '
      '(la timeline embarquée a été retirée, cf. entête de fichier)',
      (tester) async {
        final receipts = List.generate(
          5,
          (i) => _makeReceipt(id: 'r-$i', periodStart: DateTime(2026, i + 1)),
        );
        await tester.pumpWidget(_buildSection(receipts));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tile_receipts_summary')), findsOneWidget);
        expect(find.byType(ListTile), findsOneWidget);
      },
    );

    testWidgets('quittance annulée → comptée dans le total (cohérence avec le '
        'bandeau de la page complète, qui compte aussi les annulées)', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r-1'),
        _makeReceipt(id: 'r-voided', isVoided: true),
      ];
      await tester.pumpWidget(_buildSection(receipts));
      await tester.pumpAndSettle();
      expect(find.text('2 quittances'), findsOneWidget);
    });

    testWidgets(
      'tap sur la ligne de synthèse navigue vers /leases/:id/receipts',
      (tester) async {
        await tester.pumpWidget(_buildSection([_makeReceipt(id: 'r-1')]));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tile_receipts_summary')));
        await tester.pumpAndSettle();
        expect(find.text('Toutes les quittances'), findsOneWidget);
      },
    );
  });
}

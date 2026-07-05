/// Tests widget de [ReceiptsListSection].
///
/// Couvre : liste vide, liste avec items (pills), bouton "Voir toutes".
///
/// Note : ReceiptsListSection utilise désormais ReceiptsTimelineView
/// (FEAT-012 Phase 4). Les tests vérifient les pills via StatusPill
/// plutôt que les anciennes clés de ReceiptListTile.
library;

import 'dart:typed_data';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/receipts_list_section.dart';
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
  bool isVoided = false,
  bool isStale = false,
  DocumentType documentType = DocumentType.quittance,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: const ['pay-1'],
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
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
      // Route cible du lien "Voir toutes les quittances".
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
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
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

    testWidgets('liste avec items → pills statut visibles', (tester) async {
      final receipts = [_makeReceipt(id: 'r-1'), _makeReceipt(id: 'r-2')];
      await tester.pumpWidget(_buildSection(receipts));
      await tester.pumpAndSettle();
      // Avec paymentIds non vide → pills "Payée" visibles.
      expect(find.text('Payée'), findsWidgets);
    });

    testWidgets('badge "Annulée" si isVoided = true', (tester) async {
      await tester.pumpWidget(
        _buildSection([_makeReceipt(id: 'r-voided', isVoided: true)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsOneWidget);
    });

    testWidgets('badge "Périmée" si isStale = true et non voided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection([_makeReceipt(id: 'r-stale', isStale: true)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Périmée'), findsOneWidget);
    });

    testWidgets(
      'pas de badge "Périmée" si isStale ET isVoided (déjà "Annulée")',
      (tester) async {
        await tester.pumpWidget(
          _buildSection([
            _makeReceipt(id: 'r-both', isVoided: true, isStale: true),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Annulée'), findsOneWidget);
        expect(find.text('Périmée'), findsNothing);
      },
    );

    testWidgets(
      '"Voir toutes les quittances" visible quand la liste est non vide',
      (tester) async {
        await tester.pumpWidget(_buildSection([_makeReceipt(id: 'r-1')]));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_see_all_receipts')), findsOneWidget);
      },
    );

    testWidgets('"Voir toutes les quittances" absent quand la liste est vide', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection([]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_see_all_receipts')), findsNothing);
    });

    testWidgets(
      '"Voir toutes les quittances" navigue vers la page quittances',
      (tester) async {
        await tester.pumpWidget(_buildSection([_makeReceipt(id: 'r-1')]));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_see_all_receipts')));
        await tester.pumpAndSettle();
        expect(find.text('Toutes les quittances'), findsOneWidget);
      },
    );
  });
}

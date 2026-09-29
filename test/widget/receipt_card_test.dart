/// Tests widget de [ReceiptCard].
///
/// Couvre : chiffre clé + légende, menu ⋮ (annulée → pas d'item Annuler),
/// meta périmée, présence de [ShareReceiptButton].
library;

import 'dart:typed_data';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/receipts/application/void_receipt_controller.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipt_card.dart';
import 'package:easyrent/features/receipts/presentation/widgets/share_receipt_button.dart';
import 'package:easyrent/features/receipts/presentation/widgets/void_receipt_dialog.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements ReceiptsRepository {
  final List<String> renderedPdfIds = [];

  @override
  Future<List<Receipt>> listForLease(String leaseId) async => [];
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
  Future<String> signedUrl(String pdfPath) async => 'https://example.com/r.pdf';
  @override
  Future<void> voidReceipt(String id, String reason) async {}
  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async {
    renderedPdfIds.add(receiptId);
    return Uint8List(0);
  }
}

/// Contrôleur d'annulation figé en `VoidReceiptSubmitting`.
class _SubmittingVoidController extends VoidReceiptController {
  _SubmittingVoidController(super.ref) {
    state = const VoidReceiptSubmitting();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Receipt _makeReceipt({
  String id = 'r1',
  DateTime? periodStart,
  bool isVoided = false,
  bool isStale = false,
  List<String> paymentIds = const [],
  String? voidedReason,
}) {
  final start = periodStart ?? DateTime(2026, 3, 1);
  return Receipt(
    id: id,
    landlordId: 'landlord-1',
    leaseId: 'lease-1',
    paymentIds: paymentIds,
    periodStart: start,
    periodEnd: start.add(const Duration(days: 30)),
    totalCents: 120000,
    rentCents: 110000,
    chargesCents: 10000,
    documentType: DocumentType.quittance,
    pdfPath: 'l-1/$id.pdf',
    isVoided: isVoided,
    voidedAt: isVoided ? start.add(const Duration(days: 10)) : null,
    voidedReason: voidedReason,
    isStale: isStale,
    generatedAt: start.add(const Duration(days: 5)),
    createdAt: start.add(const Duration(days: 5)),
  );
}

Widget _buildCard(
  Receipt receipt, {
  _FakeRepo? repo,
  bool voidSubmitting = false,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: ReceiptCard(receipt: receipt, leaseId: 'lease-1'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      receiptsRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
      if (voidSubmitting)
        voidReceiptControllerProvider.overrideWith(
          (ref, _) => _SubmittingVoidController(ref),
        ),
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
  group('ReceiptCard', () {
    testWidgets('chiffre clé (montant) + légende "loyer + charges"', (
      tester,
    ) async {
      final receipt = _makeReceipt();

      await tester.pumpWidget(_buildCard(receipt));
      await tester.pumpAndSettle();

      expect(find.textContaining('200,00'), findsOneWidget);
      expect(find.text('loyer + charges'), findsOneWidget);
    });

    testWidgets('quittance annulée — menu sans item Annuler', (tester) async {
      final receipt = _makeReceipt(
        id: 'r-void',
        isVoided: true,
        voidedReason: 'Erreur de montant',
      );

      await tester.pumpWidget(_buildCard(receipt));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_menu_r-void')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_void_card_r-void')), findsNothing);
      expect(find.byKey(const Key('btn_pdf_card_r-void')), findsOneWidget);
    });

    testWidgets('quittance périmée — meta "Quittance périmée" visible', (
      tester,
    ) async {
      final receipt = _makeReceipt(id: 'r-stale', isStale: true);

      await tester.pumpWidget(_buildCard(receipt));
      await tester.pumpAndSettle();

      expect(find.text('Quittance périmée'), findsOneWidget);
    });

    testWidgets('ShareReceiptButton présent', (tester) async {
      final receipt = _makeReceipt();

      await tester.pumpWidget(_buildCard(receipt));
      await tester.pumpAndSettle();

      expect(find.byType(ShareReceiptButton), findsOneWidget);
    });

    testWidgets('quittance active — menu avec item PDF et Annuler', (
      tester,
    ) async {
      final receipt = _makeReceipt(id: 'r-active');

      await tester.pumpWidget(_buildCard(receipt));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_menu_r-active')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_pdf_card_r-active')), findsOneWidget);
      expect(find.byKey(const Key('btn_void_card_r-active')), findsOneWidget);
    });

    testWidgets('tap sur la carte → ouvre le PDF (renderPdfBytes appelé)', (
      tester,
    ) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(
        _buildCard(_makeReceipt(id: 'r-tap'), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_card_r-tap')));
      await tester.pumpAndSettle();

      expect(repo.renderedPdfIds, ['r-tap']);
    });

    testWidgets('menu ⋮ → "Ouvrir le PDF" → renderPdfBytes appelé', (
      tester,
    ) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(
        _buildCard(_makeReceipt(id: 'r-pdf'), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_menu_r-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_pdf_card_r-pdf')));
      await tester.pumpAndSettle();

      expect(repo.renderedPdfIds, ['r-pdf']);
    });

    testWidgets('menu ⋮ → "Annuler" → ouvre le dialogue de confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(_buildCard(_makeReceipt(id: 'r-void-dlg')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_menu_r-void-dlg')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_void_card_r-void-dlg')));
      await tester.pumpAndSettle();

      expect(find.byType(VoidReceiptDialog), findsOneWidget);
    });

    testWidgets('annulation en cours (Submitting) — item Annuler absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildCard(_makeReceipt(id: 'r-busy'), voidSubmitting: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt_menu_r-busy')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_void_card_r-busy')), findsNothing);
      expect(find.byKey(const Key('btn_pdf_card_r-busy')), findsOneWidget);
    });
  });
}

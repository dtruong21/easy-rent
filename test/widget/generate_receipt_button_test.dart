/// Tests widget de [GenerateReceiptButton].
///
/// Couvre : submit → success (dialog preview), error (SnackBar),
/// profileIncomplete (dialog profil), état submitting (spinner).
library;

import 'dart:async';

import 'package:easyrent/core/utils/edge_function_error_mapper.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/generate_receipt_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeReceiptsRepo implements ReceiptsRepository {
  final ReceiptGenerationResult? _result;
  final Exception? _exception;

  const _FakeReceiptsRepo({
    ReceiptGenerationResult? result,
    Exception? exception,
  }) : _result = result,
       _exception = exception;

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
  }) async {
    if (_exception != null) throw _exception;
    if (_result != null) return _result;
    throw StateError('no result configured');
  }

  @override
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ReceiptGenerationResult _makeResult() => ReceiptGenerationResult(
  receiptId: 'r-1',
  pdfUrl: 'https://example.com/r-1.pdf',
  documentType: DocumentType.quittance,
  totalCents: 90000,
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
);

Widget _buildWidget({required ReceiptsRepository repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: GenerateReceiptButton(paymentId: 'pay-1', leaseId: 'lease-1'),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, _) => const Scaffold(body: Text('Profile Page')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GenerateReceiptButton', () {
    testWidgets('icône receipt_long_outlined visible par défaut', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(repo: _FakeReceiptsRepo(result: _makeResult())),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_generate_receipt_pay-1')),
        findsOneWidget,
      );
    });

    testWidgets('clic → state submitting → spinner affiché', (tester) async {
      // Completer pour bloquer la génération sans laisser de timer pendant.
      final completer = Completer<ReceiptGenerationResult>();
      var generating = false;
      final repo = _ControlledRepo(() async {
        generating = true;
        return completer.future;
      });

      await tester.pumpWidget(_buildWidget(repo: repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pump(); // laisse le future démarrer

      expect(generating, true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Compléter pour nettoyer le future avant la fin du test.
      completer.complete(_makeResult());
      await tester.pumpAndSettle();
    });

    testWidgets('succès → dialog preview affiché', (tester) async {
      await tester.pumpWidget(
        _buildWidget(repo: _FakeReceiptsRepo(result: _makeResult())),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_receipt_preview')), findsOneWidget);
    });

    testWidgets('erreur → SnackBar affiché', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          repo: _FakeReceiptsRepo(
            exception: const ReceiptGenerationException('pdf error'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('profileIncomplete → dialog ProfileIncompleteDialog affiché', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(
          repo: _FakeReceiptsRepo(
            exception: const ProfileIncompleteException(
              missing: ['full_name', 'address'],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dialog_profile_incomplete')),
        findsOneWidget,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Repo contrôlable pour test submitting
// ---------------------------------------------------------------------------

class _ControlledRepo implements ReceiptsRepository {
  final Future<ReceiptGenerationResult> Function() _generateFn;

  _ControlledRepo(this._generateFn);

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
  }) => _generateFn();

  @override
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async =>
      throw UnimplementedError();
}

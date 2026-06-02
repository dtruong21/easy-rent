/// Tests widget de [SendReceiptButton].
///
/// Couvre :
/// - icône mail_outline si jamais envoyée
/// - icône mark_email_read_outlined si déjà envoyée
/// - bouton désactivé (gris) si voided ou stale
/// - clic → dialog confirmingResend si déjà envoyée
/// - clic → succès → SnackBar
/// - clic → tenantNoEmail → SnackBar avec message email
/// - clic → rateLimited → SnackBar quota
library;

import 'dart:async';

import 'package:easyrent/core/utils/edge_function_error_mapper.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/send_receipt_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements ReceiptsRepository {
  final Completer<Receipt>? _completer;
  final Exception? _exception;
  final Receipt? _successReceipt;

  const _FakeRepo({
    Completer<Receipt>? completer,
    Exception? exception,
    Receipt? successReceipt,
  }) : _completer = completer,
       _exception = exception,
       _successReceipt = successReceipt;

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async {
    if (_exception != null) throw _exception;
    if (_completer != null) return _completer.future;
    if (_successReceipt != null) return _successReceipt;
    throw StateError('no result configured');
  }

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
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  bool isVoided = false,
  bool isStale = false,
  DateTime? sentAt,
  String? sentToEmail,
}) => Receipt(
  id: 'r-1',
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: ['pay-1'],
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
  totalCents: 90000,
  rentCents: 85000,
  chargesCents: 5000,
  documentType: DocumentType.quittance,
  pdfPath: 'landlord-1/r-1.pdf',
  isVoided: isVoided,
  isStale: isStale,
  generatedAt: DateTime(2026, 2, 1),
  createdAt: DateTime(2026, 2, 1),
  sentAt: sentAt,
  sentToEmail: sentToEmail,
);

Receipt _makeSentReceipt() => _makeReceipt(
  sentAt: DateTime(2026, 5, 1, 10),
  sentToEmail: 'loc@example.com',
);

Widget _buildWidget({
  required Receipt receipt,
  required ReceiptsRepository repo,
  String? tenantId,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SendReceiptButton(
            receipt: receipt,
            leaseId: 'lease-1',
            tenantId: tenantId,
          ),
        ),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        builder: (context, _) => const Scaffold(body: Text('Tenant Edit Page')),
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
  group('SendReceiptButton — état idle non envoyé', () {
    testWidgets('icône mail_outline présente si jamais envoyée', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(
            successReceipt: null,
            exception: TenantNoEmailException(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('btn_send_receipt_r-1')), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    });
  });

  group('SendReceiptButton — état idle déjà envoyé', () {
    testWidgets('icône mark_email_read_outlined si déjà envoyée', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeSentReceipt(),
          repo: const _FakeRepo(exception: EmailQuotaExceededException()),
        ),
      );
      await tester.pump();
      // Le bouton avec key btn_send_receipt_r-1 existe.
      final btn = find.byKey(const Key('btn_send_receipt_r-1'));
      expect(btn, findsOneWidget);
      // L'icône mail_outline est absente (quittance déjà envoyée).
      expect(find.byIcon(Icons.mail_outline), findsNothing);
      // L'icône mark_email_read_outlined est présente.
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
    });
  });

  group('SendReceiptButton — voided/stale désactivé', () {
    testWidgets('bouton désactivé si voided', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(isVoided: true),
          repo: const _FakeRepo(),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_send_receipt_disabled_r-1')),
        findsOneWidget,
      );
    });

    testWidgets('bouton désactivé si stale', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(isStale: true),
          repo: const _FakeRepo(),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_send_receipt_disabled_r-1')),
        findsOneWidget,
      );
    });
  });

  group('SendReceiptButton — état submitting', () {
    testWidgets('clic → spinner CircularProgressIndicator', (tester) async {
      final completer = Completer<Receipt>();
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: _FakeRepo(completer: completer),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Nettoyer le completer pour éviter un timer pendant.
      completer.completeError(Exception('cleanup'));
      await tester.pumpAndSettle();
    });
  });

  group('SendReceiptButton — succès', () {
    testWidgets('succès → SnackBar affiché', (tester) async {
      final sentReceipt = _makeReceipt(
        sentAt: DateTime(2026, 6, 1),
        sentToEmail: 'loc@example.com',
      );
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: _FakeRepo(successReceipt: sentReceipt),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      // Le SnackBar contient "envoyée".
      expect(find.textContaining('envoyée'), findsOneWidget);
    });
  });

  group('SendReceiptButton — tenantNoEmail', () {
    testWidgets('tenantNoEmail → SnackBar avec message email', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(exception: TenantNoEmailException()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('email'), findsWidgets);
    });

    testWidgets('tenantNoEmail avec tenantId → SnackBar avec bouton Modifier', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(exception: TenantNoEmailException()),
          tenantId: 'tenant-1',
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
    });
  });

  group('SendReceiptButton — rateLimited', () {
    testWidgets('rateLimited → SnackBar quota', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(exception: EmailQuotaExceededException()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Quota'), findsOneWidget);
    });
  });

  group('SendReceiptButton — dialog confirmingResend', () {
    testWidgets('clic sur quittance déjà envoyée → dialog confirmation', (
      tester,
    ) async {
      // Le repo success simulera l'envoi pour confirmer.
      final sentReceipt = _makeSentReceipt();
      await tester.pumpWidget(
        _buildWidget(
          receipt: sentReceipt,
          repo: _FakeRepo(successReceipt: sentReceipt),
        ),
      );
      await tester.pump();

      // Le sendReceiptControllerProvider est autoDispose — on override l'état.
      // On clique pour déclencher confirmingResend.
      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      // Le dialog ConfirmResendDialog doit être ouvert.
      expect(find.byKey(const Key('dialog_confirm_resend')), findsOneWidget);
    });

    testWidgets('annuler le dialog → dialog fermé', (tester) async {
      final sentReceipt = _makeSentReceipt();
      await tester.pumpWidget(
        _buildWidget(
          receipt: sentReceipt,
          repo: _FakeRepo(successReceipt: sentReceipt),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_send_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_resend_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsNothing);
    });
  });
}

/// Tests de la méthode [ReceiptsRepository.sendReceipt] via un fake in-memory.
///
/// Couvre :
/// - succès → retourne la quittance mise à jour
/// - TenantNoEmailException propagée
/// - ReceiptInvalidForSendException propagée
/// - PdfUnavailableException propagée
/// - EmailQuotaExceededException propagée
/// - ReceiptSendException propagée
/// - ReceiptNotFoundException si receiptId introuvable
library;

import 'package:easyrent/core/utils/edge_function_error_mapper.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory pour sendReceipt
// ---------------------------------------------------------------------------

class _FakeSendReceiptsRepo implements ReceiptsRepository {
  final List<Receipt> _receipts = [];

  /// Si non-null, `sendReceipt` lève cette exception.
  Exception? _sendException;

  void addReceipt(Receipt r) => _receipts.add(r);

  void simulateSendException(Exception e) => _sendException = e;

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async {
    if (_sendException != null) throw _sendException!;
    final match = _receipts.where((r) => r.id == receiptId);
    if (match.isEmpty) throw ReceiptNotFoundException(receiptId);
    // Simule la mise à jour avec sentAt/sentToEmail.
    final updated = match.first.copyWith(
      sentAt: DateTime(2026, 6, 1, 12),
      sentToEmail: 'locataire@example.com',
    );
    return updated;
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
// Helper
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  String id = 'receipt-1',
  bool isVoided = false,
  bool isStale = false,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: ['pay-1'],
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
  totalCents: 90000,
  rentCents: 85000,
  chargesCents: 5000,
  documentType: DocumentType.quittance,
  pdfPath: 'landlord-1/$id.pdf',
  isVoided: isVoided,
  isStale: isStale,
  generatedAt: DateTime(2026, 2, 1),
  createdAt: DateTime(2026, 2, 1),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeSendReceiptsRepo repo;

  setUp(() => repo = _FakeSendReceiptsRepo());

  group('sendReceipt — succès', () {
    test('retourne la quittance avec sentAt et sentToEmail remplis', () async {
      repo.addReceipt(_makeReceipt());
      final updated = await repo.sendReceipt(receiptId: 'receipt-1');
      expect(updated.sentAt, isNotNull);
      expect(updated.sentToEmail, 'locataire@example.com');
    });

    test('hasBeenSent est true après sendReceipt', () async {
      repo.addReceipt(_makeReceipt());
      final updated = await repo.sendReceipt(receiptId: 'receipt-1');
      expect(updated.hasBeenSent, true);
    });
  });

  group('sendReceipt — ReceiptNotFoundException', () {
    test('lève ReceiptNotFoundException si id introuvable', () async {
      expect(
        () => repo.sendReceipt(receiptId: 'inconnu'),
        throwsA(isA<ReceiptNotFoundException>()),
      );
    });
  });

  group('sendReceipt — exceptions typées propagées', () {
    test('TenantNoEmailException remonte', () async {
      repo.simulateSendException(const TenantNoEmailException());
      expect(
        () => repo.sendReceipt(receiptId: 'r-1'),
        throwsA(isA<TenantNoEmailException>()),
      );
    });

    test('ReceiptInvalidForSendException remonte', () async {
      repo.simulateSendException(const ReceiptInvalidForSendException());
      expect(
        () => repo.sendReceipt(receiptId: 'r-1'),
        throwsA(isA<ReceiptInvalidForSendException>()),
      );
    });

    test('PdfUnavailableException remonte', () async {
      repo.simulateSendException(const PdfUnavailableException());
      expect(
        () => repo.sendReceipt(receiptId: 'r-1'),
        throwsA(isA<PdfUnavailableException>()),
      );
    });

    test('EmailQuotaExceededException remonte', () async {
      repo.simulateSendException(const EmailQuotaExceededException());
      expect(
        () => repo.sendReceipt(receiptId: 'r-1'),
        throwsA(isA<EmailQuotaExceededException>()),
      );
    });

    test('ReceiptSendException remonte', () async {
      repo.simulateSendException(
        const ReceiptSendException('erreur générique'),
      );
      expect(
        () => repo.sendReceipt(receiptId: 'r-1'),
        throwsA(isA<ReceiptSendException>()),
      );
    });
  });

  group('ReceiptSendException.toString', () {
    test('contient le message', () {
      const ex = ReceiptSendException('échec envoi');
      expect(ex.toString(), contains('échec envoi'));
    });
  });
}

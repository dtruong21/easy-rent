/// Tests des transitions d'état de [SendReceiptController].
///
/// Couvre :
/// - initiate → idle si receipt jamais envoyé → submitting → success
/// - initiate → confirmingResend si receipt déjà envoyé
/// - confirmResend → submitting → success
/// - submitting → tenantNoEmail
/// - submitting → rateLimited
/// - submitting → error (ReceiptInvalidForSendException)
/// - submitting → error (PdfUnavailableException)
/// - submitting → error (ReceiptSendException)
/// - submitting → error (exception inconnue)
/// - reset → idle
library;

import 'package:easyrent/core/utils/edge_function_error_mapper.dart';
import 'package:easyrent/features/receipts/application/send_receipt_controller.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/domain/send_receipt_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements ReceiptsRepository {
  Receipt? _updatedReceipt;
  Exception? _sendException;

  void simulateSuccess(Receipt updated) => _updatedReceipt = updated;
  void simulateSendException(Exception e) => _sendException = e;

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async {
    if (_sendException != null) throw _sendException!;
    if (_updatedReceipt != null) return _updatedReceipt!;
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

Receipt _makeUpdatedReceipt() => _makeReceipt(
  sentAt: DateTime(2026, 6, 1, 12),
  sentToEmail: 'loc@example.com',
);

ProviderContainer _makeContainer(_FakeRepo repo) {
  return ProviderContainer(
    overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = _makeContainer(repo);
  });

  tearDown(() => container.dispose());

  group('initiate — premier envoi', () {
    test('état initial = idle', () {
      expect(
        container.read(sendReceiptControllerProvider),
        isA<SendReceiptIdle>(),
      );
    });

    test('receipt non envoyé → submitting → success après initiate', () async {
      repo.simulateSuccess(_makeUpdatedReceipt());
      final notifier = container.read(sendReceiptControllerProvider.notifier);
      await notifier.initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      expect(state, isA<SendReceiptSuccess>());
    });

    test('success state contient sentAt et sentToEmail', () async {
      repo.simulateSuccess(_makeUpdatedReceipt());
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      expect(state, isA<SendReceiptSuccess>());
      if (state case SendReceiptSuccess(:final sentAt, :final sentToEmail)) {
        expect(sentAt, isNotNull);
        expect(sentToEmail, isNotEmpty);
      }
    });
  });

  group('initiate — renvoi (hasBeenSent = true)', () {
    test(
      'receipt déjà envoyé → confirmingResend (sans appel réseau)',
      () async {
        final receipt = _makeReceipt(
          sentAt: DateTime(2026, 5, 1),
          sentToEmail: 'loc@example.com',
        );
        await container
            .read(sendReceiptControllerProvider.notifier)
            .initiate(receipt: receipt, leaseId: 'lease-1');
        final state = container.read(sendReceiptControllerProvider);
        expect(state, isA<SendReceiptConfirmingResend>());
      },
    );

    test('confirmingResend contient la date et le maskedEmail', () async {
      final sentAt = DateTime(2026, 5, 1);
      final receipt = _makeReceipt(
        sentAt: sentAt,
        sentToEmail: 'loc@example.com',
      );
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: receipt, leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      if (state case SendReceiptConfirmingResend(
        :final previousSentAt,
        :final previousMaskedEmail,
      )) {
        expect(previousSentAt, sentAt);
        expect(previousMaskedEmail, isNotEmpty);
        expect(previousMaskedEmail, contains('@'));
      } else {
        fail('attendait SendReceiptConfirmingResend');
      }
    });
  });

  group('confirmResend', () {
    test('confirmResend → success après confirmation', () async {
      repo.simulateSuccess(_makeUpdatedReceipt());
      final receipt = _makeReceipt(
        sentAt: DateTime(2026, 5, 1),
        sentToEmail: 'loc@example.com',
      );
      await container
          .read(sendReceiptControllerProvider.notifier)
          .confirmResend(receipt: receipt, leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      expect(state, isA<SendReceiptSuccess>());
    });
  });

  group('tenantNoEmail', () {
    test('TenantNoEmailException → état tenantNoEmail', () async {
      repo.simulateSendException(const TenantNoEmailException());
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      expect(
        container.read(sendReceiptControllerProvider),
        isA<SendReceiptTenantNoEmail>(),
      );
    });
  });

  group('rateLimited', () {
    test('EmailQuotaExceededException → état rateLimited', () async {
      repo.simulateSendException(const EmailQuotaExceededException());
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      expect(
        container.read(sendReceiptControllerProvider),
        isA<SendReceiptRateLimited>(),
      );
    });
  });

  group('error — exceptions typées', () {
    test(
      'ReceiptInvalidForSendException → état error avec message annulée/périmée',
      () async {
        repo.simulateSendException(const ReceiptInvalidForSendException());
        await container
            .read(sendReceiptControllerProvider.notifier)
            .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
        final state = container.read(sendReceiptControllerProvider);
        expect(state, isA<SendReceiptError>());
        if (state case SendReceiptError(:final message)) {
          expect(message.toLowerCase(), contains('annulée'));
        }
      },
    );

    test('PdfUnavailableException → état error avec message PDF', () async {
      repo.simulateSendException(const PdfUnavailableException());
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      expect(state, isA<SendReceiptError>());
      if (state case SendReceiptError(:final message)) {
        expect(message.toLowerCase(), contains('pdf'));
      }
    });

    test(
      'ReceiptSendException → état error avec le message de l\'exception',
      () async {
        repo.simulateSendException(const ReceiptSendException('erreur custom'));
        await container
            .read(sendReceiptControllerProvider.notifier)
            .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
        final state = container.read(sendReceiptControllerProvider);
        expect(state, isA<SendReceiptError>());
        if (state case SendReceiptError(:final message)) {
          expect(message, contains('erreur custom'));
        }
      },
    );

    test('exception inconnue → état error avec message générique', () async {
      repo.simulateSendException(Exception('inconnu'));
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      final state = container.read(sendReceiptControllerProvider);
      expect(state, isA<SendReceiptError>());
    });
  });

  group('reset', () {
    test('reset → idle', () async {
      repo.simulateSendException(const TenantNoEmailException());
      await container
          .read(sendReceiptControllerProvider.notifier)
          .initiate(receipt: _makeReceipt(), leaseId: 'lease-1');
      // était tenantNoEmail
      container.read(sendReceiptControllerProvider.notifier).reset();
      expect(
        container.read(sendReceiptControllerProvider),
        isA<SendReceiptIdle>(),
      );
    });
  });
}

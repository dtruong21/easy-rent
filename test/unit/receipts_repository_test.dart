/// Tests du contrat [ReceiptsRepository] via un fake in-memory.
///
/// NOTE : [FirestoreReceiptsRepository] utilise [FirebaseFirestore] et les
/// Cloud Functions callables, qui dépendent de [FirebaseFirestore.instance] —
/// non initialisé en test unitaire.
/// On teste le contrat de l'interface, les invariants du fake, et les
/// exceptions (ProfileIncompleteException, ReceiptNotFoundException).
library;

import 'dart:typed_data';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _InMemoryReceiptsRepository implements ReceiptsRepository {
  final List<Receipt> _receipts = [];
  final Map<String, String> _signedUrls = {};

  /// Si non-null, simulate() déclenche une [ProfileIncompleteException].
  List<String>? _profileIncompleteFields;

  /// Si non-null, lève cette exception lors de generate().
  Exception? _generateException;

  void simulateProfileIncomplete(List<String> fields) {
    _profileIncompleteFields = fields;
  }

  void simulateGenerateException(Exception e) {
    _generateException = e;
  }

  void addSignedUrl(String pdfPath, String url) {
    _signedUrls[pdfPath] = url;
  }

  @override
  Future<List<Receipt>> listForLease(String leaseId) async {
    final filtered = _receipts.where((r) => r.leaseId == leaseId).toList()
      ..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    return filtered;
  }

  @override
  Future<Receipt> getById(String id) async {
    final matches = _receipts.where((r) => r.id == id);
    if (matches.isEmpty) throw ReceiptNotFoundException(id);
    return matches.first;
  }

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    if (_profileIncompleteFields != null) {
      throw ProfileIncompleteException(missing: _profileIncompleteFields!);
    }
    if (_generateException != null) {
      throw _generateException!;
    }
    // Simule une génération réussie.
    final result = ReceiptGenerationResult(
      receiptId: 'receipt-generated',
      pdfUrl: 'https://example.com/signed.pdf',
      documentType: DocumentType.quittance,
      totalCents: 90000,
      periodStart: periodStart ?? DateTime(2026, 1, 1),
      periodEnd: periodEnd ?? DateTime(2026, 1, 31),
    );
    return result;
  }

  @override
  Future<String> signedUrl(String pdfPath) async {
    final url = _signedUrls[pdfPath];
    if (url == null) {
      throw ReceiptNotFoundException(pdfPath);
    }
    return url;
  }

  @override
  Future<void> voidReceipt(String id, String reason) async {
    final idx = _receipts.indexWhere((r) => r.id == id);
    if (idx == -1) throw ReceiptNotFoundException(id);
    _receipts[idx] = _receipts[idx].copyWith(
      isVoided: true,
      voidedReason: reason,
    );
  }

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async {
    final idx = _receipts.indexWhere((r) => r.id == receiptId);
    if (idx == -1) throw ReceiptNotFoundException(receiptId);
    final sharedAt = DateTime(2026, 6, 1, 12);
    _receipts[idx] = _receipts[idx].copyWith(
      sentAt: sharedAt,
      sentToEmail: tenantEmail,
    );
    return _receipts[idx];
  }

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  String id = 'receipt-1',
  String leaseId = 'lease-1',
  DateTime? periodStart,
}) {
  final start = periodStart ?? DateTime(2026, 1, 1);
  return Receipt(
    id: id,
    landlordId: 'landlord-1',
    leaseId: leaseId,
    paymentIds: ['pay-1'],
    periodStart: start,
    periodEnd: DateTime(2026, 1, 31),
    totalCents: 90000,
    rentCents: 85000,
    chargesCents: 5000,
    documentType: DocumentType.quittance,
    pdfPath: 'landlord-1/$id.pdf',
    isVoided: false,
    isStale: false,
    generatedAt: DateTime(2026, 2, 1),
    createdAt: DateTime(2026, 2, 1),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _InMemoryReceiptsRepository repo;

  setUp(() => repo = _InMemoryReceiptsRepository());

  // ---------------------------------------------------------------------------
  group('listForLease', () {
    test('liste vide → []', () async {
      final result = await repo.listForLease('lease-1');
      expect(result, isEmpty);
    });

    test('filtre par leaseId', () async {
      repo._receipts.add(_makeReceipt(id: 'r-1', leaseId: 'lease-1'));
      repo._receipts.add(_makeReceipt(id: 'r-2', leaseId: 'lease-2'));
      final result = await repo.listForLease('lease-1');
      expect(result.length, 1);
      expect(result.first.id, 'r-1');
    });

    test('tri period_start DESC', () async {
      repo._receipts.add(
        _makeReceipt(
          id: 'r-old',
          leaseId: 'lease-1',
          periodStart: DateTime(2026, 1, 1),
        ),
      );
      repo._receipts.add(
        _makeReceipt(
          id: 'r-new',
          leaseId: 'lease-1',
          periodStart: DateTime(2026, 3, 1),
        ),
      );
      final result = await repo.listForLease('lease-1');
      expect(result.first.id, 'r-new');
      expect(result.last.id, 'r-old');
    });

    test('inclut les quittances voided', () async {
      repo._receipts.add(_makeReceipt().copyWith(isVoided: true));
      final result = await repo.listForLease('lease-1');
      expect(result.length, 1);
      expect(result.first.isVoided, true);
    });
  });

  // ---------------------------------------------------------------------------
  group('getById', () {
    test('retourne la quittance si trouvée', () async {
      repo._receipts.add(_makeReceipt(id: 'r-42'));
      final r = await repo.getById('r-42');
      expect(r.id, 'r-42');
    });

    test('lève ReceiptNotFoundException si introuvable', () async {
      expect(
        () => repo.getById('inconnu'),
        throwsA(isA<ReceiptNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('generate', () {
    test('retourne un ReceiptGenerationResult en cas de succès', () async {
      final result = await repo.generate(paymentIds: ['pay-1']);
      expect(result.receiptId, 'receipt-generated');
      expect(result.pdfUrl, isNotEmpty);
      expect(result.documentType, DocumentType.quittance);
    });

    test('lève ProfileIncompleteException si profil incomplet', () async {
      repo.simulateProfileIncomplete(['full_name', 'address']);
      expect(
        () => repo.generate(paymentIds: ['pay-1']),
        throwsA(isA<ProfileIncompleteException>()),
      );
    });

    test('ProfileIncompleteException contient les champs manquants', () async {
      repo.simulateProfileIncomplete(['full_name']);
      try {
        await repo.generate(paymentIds: ['pay-1']);
        fail('should throw');
      } on ProfileIncompleteException catch (e) {
        expect(e.missing, contains('full_name'));
      }
    });

    test('propage d\'autres exceptions', () async {
      repo.simulateGenerateException(
        const ReceiptGenerationException('pdf error'),
      );
      expect(
        () => repo.generate(paymentIds: ['pay-1']),
        throwsA(isA<ReceiptGenerationException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('signedUrl', () {
    test('retourne l\'URL si le chemin est connu', () async {
      repo.addSignedUrl('landlord-1/r-1.pdf', 'https://signed.url/r-1.pdf');
      final url = await repo.signedUrl('landlord-1/r-1.pdf');
      expect(url, 'https://signed.url/r-1.pdf');
    });

    test('lève une exception si le chemin est inconnu', () async {
      expect(
        () => repo.signedUrl('inconnu.pdf'),
        throwsA(isA<ReceiptNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('voidReceipt', () {
    test('marque la quittance comme voided', () async {
      repo._receipts.add(_makeReceipt(id: 'r-1'));
      await repo.voidReceipt('r-1', 'Erreur de montant');
      final r = await repo.getById('r-1');
      expect(r.isVoided, true);
      expect(r.voidedReason, 'Erreur de montant');
    });

    test('lève ReceiptNotFoundException si introuvable', () async {
      expect(
        () => repo.voidReceipt('inconnu', 'motif'),
        throwsA(isA<ReceiptNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('markReceiptAsShared', () {
    test('marque la quittance avec sentAt et sentToEmail', () async {
      repo._receipts.add(_makeReceipt(id: 'r-1'));
      final updated = await repo.markReceiptAsShared(
        receiptId: 'r-1',
        tenantEmail: 'locataire@example.com',
      );
      expect(updated.sentAt, isNotNull);
      expect(updated.sentToEmail, 'locataire@example.com');
    });

    test('hasBeenShared est true après markReceiptAsShared', () async {
      repo._receipts.add(_makeReceipt(id: 'r-1'));
      final updated = await repo.markReceiptAsShared(
        receiptId: 'r-1',
        tenantEmail: 'locataire@example.com',
      );
      expect(updated.hasBeenShared, true);
    });

    test('lève ReceiptNotFoundException si id introuvable', () async {
      expect(
        () => repo.markReceiptAsShared(
          receiptId: 'inconnu',
          tenantEmail: 'test@example.com',
        ),
        throwsA(isA<ReceiptNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('ReceiptNotFoundException.toString', () {
    test('contient l\'id', () {
      final ex = ReceiptNotFoundException('r-42');
      expect(ex.toString(), contains('r-42'));
    });
  });
}

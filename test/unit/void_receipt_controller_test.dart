/// Test unitaire d'isolation de [voidReceiptControllerProvider].
///
/// Régression du bug multi-lignes : le provider était global et partagé par
/// toutes les cartes/menus de quittance montés, si bien qu'annuler une
/// quittance faisait déborder l'état (spinner + SnackBar) sur toutes les
/// lignes. Depuis, le provider est `.family` keyé par `receiptId` : ce test
/// prouve qu'annuler r-1 laisse r-2 au repos.
library;

import 'dart:typed_data';

import 'package:easyrent/features/receipts/application/void_receipt_controller.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repo dont `voidReceipt` échoue — pour faire atterrir le contrôleur dans
/// [VoidReceiptError] sans passer par le chemin de succès (qui invaliderait
/// d'autres providers non montés dans ce container).
class _ThrowingRepo implements ReceiptsRepository {
  const _ThrowingRepo();

  @override
  Future<void> voidReceipt(String id, String reason) async {
    throw Exception('boom');
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
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

void main() {
  group('voidReceiptController — isolation par quittance (family)', () {
    test('annuler r-1 ne change pas l\'état de r-2', () async {
      final container = ProviderContainer(
        overrides: [
          receiptsRepositoryProvider.overrideWithValue(const _ThrowingRepo()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(voidReceiptControllerProvider('r-1').notifier)
          .voidReceipt(receiptId: 'r-1', reason: 'test', leaseId: 'lease-1');

      // r-1 a bien transité (vers une erreur, ici).
      expect(
        container.read(voidReceiptControllerProvider('r-1')),
        isA<VoidReceiptError>(),
      );
      // r-2 reste au repos — l'état de r-1 n'a pas débordé.
      expect(
        container.read(voidReceiptControllerProvider('r-2')),
        isA<VoidReceiptIdle>(),
      );
    });
  });
}

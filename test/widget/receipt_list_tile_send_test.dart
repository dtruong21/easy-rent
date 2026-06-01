/// Tests widget de [ReceiptListTile] — AC8 audit trail "Envoyé le …".
///
/// Couvre :
/// - subtitle sans info d'envoi si jamais envoyée
/// - subtitle avec "Envoyé le JJ/MM/YYYY à email masqué" si sentAt + sentToEmail
library;

import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipt_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements ReceiptsRepository {
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

  @override
  Future<Receipt> sendReceipt({required String receiptId}) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({DateTime? sentAt, String? sentToEmail}) => Receipt(
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
  isVoided: false,
  isStale: false,
  generatedAt: DateTime(2026, 2, 1),
  createdAt: DateTime(2026, 2, 1),
  sentAt: sentAt,
  sentToEmail: sentToEmail,
);

Widget _buildTile(Receipt receipt) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(
            child: ReceiptListTile(receipt: receipt, leaseId: 'lease-1'),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(_FakeRepo())],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ReceiptListTile — AC8 audit trail envoi', () {
    testWidgets('subtitle sans mention "Envoyé" si quittance jamais envoyée', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(_makeReceipt()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Envoyé le'), findsNothing);
    });

    testWidgets(
      'subtitle affiche "Envoyé le JJ/MM/YYYY à email masqué" si sentAt + sentToEmail',
      (tester) async {
        final receipt = _makeReceipt(
          sentAt: DateTime(2026, 6, 1),
          sentToEmail: 'locataire@example.com',
        );
        await tester.pumpWidget(_buildTile(receipt));
        await tester.pumpAndSettle();

        // La date doit être au format DD/MM/YYYY.
        expect(find.textContaining('Envoyé le 01/06/2026'), findsOneWidget);
        // L'email doit être masqué (premier char + *** + @domaine).
        expect(find.textContaining('l***@example.com'), findsOneWidget);
      },
    );

    testWidgets(
      'email masqué correctement : premier caractère + *** + @domaine',
      (tester) async {
        final receipt = _makeReceipt(
          sentAt: DateTime(2026, 5, 15),
          sentToEmail: 'jean.dupont@test.fr',
        );
        await tester.pumpWidget(_buildTile(receipt));
        await tester.pumpAndSettle();

        expect(find.textContaining('j***@test.fr'), findsOneWidget);
      },
    );
  });
}

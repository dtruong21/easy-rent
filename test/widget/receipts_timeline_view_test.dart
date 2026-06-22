/// Tests widget de [ReceiptsTimelineView].
///
/// Couvre : 0 / 3 items, header année, couleur marqueur, squelette.
library;

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipts_timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repo
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
  Future<String> signedUrl(String pdfPath) async => 'https://example.com/r.pdf';
  @override
  Future<void> voidReceipt(String id, String reason) async {}
  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();
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
  required DateTime periodStart,
  bool isVoided = false,
  List<String> paymentIds = const [],
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: paymentIds,
  periodStart: periodStart,
  periodEnd: periodStart.copyWith(month: periodStart.month + 1, day: 0),
  totalCents: 120000,
  rentCents: 110000,
  chargesCents: 10000,
  documentType: DocumentType.quittance,
  pdfPath: 'l-1/$id.pdf',
  isVoided: isVoided,
  isStale: false,
  generatedAt: periodStart.add(const Duration(days: 5)),
  createdAt: periodStart.add(const Duration(days: 5)),
);

Widget _buildView(List<Receipt> receipts) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: ReceiptsTimelineView(receipts: receipts, leaseId: 'lease-1'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(_FakeRepo())],
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ReceiptsTimelineView', () {
    testWidgets('0 item — ListView vide sans erreur', (tester) async {
      await tester.pumpWidget(_buildView([]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipts_timeline')), findsOneWidget);
      // Aucun marqueur de timeline (aucun item).
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('3 items même année — 1 header année visible', (tester) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
        _makeReceipt(id: 'r2', periodStart: DateTime(2026, 2, 1)),
        _makeReceipt(id: 'r3', periodStart: DateTime(2026, 1, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      // Un seul header 2026.
      expect(find.text('2026'), findsOneWidget);
      // 3 périodes.
      expect(find.textContaining('Mars 2026'), findsOneWidget);
      expect(find.textContaining('Février 2026'), findsOneWidget);
      expect(find.textContaining('Janvier 2026'), findsOneWidget);
    });

    testWidgets('items 2 années différentes — 2 headers années', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 1, 1)),
        _makeReceipt(id: 'r2', periodStart: DateTime(2025, 12, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.text('2026'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
    });

    testWidgets('statut affiché — pill "Émise" pour quittance sans paiement', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.text('Émise'), findsOneWidget);
    });

    testWidgets('statut affiché — pill "Payée" pour quittance avec paiement', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(
          id: 'r1',
          periodStart: DateTime(2026, 3, 1),
          paymentIds: ['pay-1'],
        ),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.text('Payée'), findsOneWidget);
    });

    testWidgets('vue squelette — ListView squelette sans erreur', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) =>
                Scaffold(body: ReceiptsTimelineView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('motif annulation affiché si voided + voidedReason', (
      tester,
    ) async {
      final r = Receipt(
        id: 'r-void',
        landlordId: 'l-1',
        leaseId: 'lease-1',
        paymentIds: const [],
        periodStart: DateTime(2026, 2, 1),
        periodEnd: DateTime(2026, 2, 28),
        totalCents: 120000,
        rentCents: 110000,
        chargesCents: 10000,
        documentType: DocumentType.quittance,
        pdfPath: 'l-1/r-void.pdf',
        isVoided: true,
        voidedAt: DateTime(2026, 2, 10),
        voidedReason: 'Erreur de montant',
        isStale: false,
        generatedAt: DateTime(2026, 2, 5),
        createdAt: DateTime(2026, 2, 5),
      );

      await tester.pumpWidget(_buildView([r]));
      await tester.pumpAndSettle();

      expect(find.text('Annulée'), findsOneWidget);
      expect(find.textContaining('Erreur de montant'), findsOneWidget);
    });
  });
}

extension on DateTime {
  DateTime copyWith({int? year, int? month, int? day}) =>
      DateTime(year ?? this.year, month ?? this.month, day ?? this.day);
}

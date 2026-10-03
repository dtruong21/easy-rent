/// Tests widget de [ReceiptsCardView].
///
/// Couvre : 0/3/6 items, tap PDF, squelette.
library;

import 'dart:typed_data';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/core/ui/cards/summary_card.dart';
import 'package:easyrent/core/ui/theme/property_color.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipt_card.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipts_card_view.dart';
import 'package:easyrent/l10n/app_localizations.dart';
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

Receipt _makeReceipt({required String id, required DateTime periodStart}) =>
    Receipt(
      id: id,
      landlordId: 'landlord-1',
      leaseId: 'lease-1',
      paymentIds: const [],
      periodStart: periodStart,
      periodEnd: periodStart.add(const Duration(days: 30)),
      totalCents: 120000,
      rentCents: 110000,
      chargesCents: 10000,
      documentType: DocumentType.quittance,
      pdfPath: 'l-1/$id.pdf',
      isVoided: false,
      isStale: false,
      generatedAt: periodStart.add(const Duration(days: 5)),
      createdAt: periodStart.add(const Duration(days: 5)),
    );

Widget _buildView(List<Receipt> receipts, {PropertyColorKey? colorKey}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: ReceiptsCardView(
            receipts: receipts,
            leaseId: 'lease-1',
            propertyColorKey: colorKey,
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(_FakeRepo())],
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
  group('ReceiptsCardView', () {
    testWidgets('0 item — aucune ReceiptCard', (tester) async {
      await tester.pumpWidget(_buildView([]));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsNothing);
    });

    testWidgets('3 items — 3 ReceiptCard', (tester) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
        _makeReceipt(id: 'r2', periodStart: DateTime(2026, 2, 1)),
        _makeReceipt(id: 'r3', periodStart: DateTime(2026, 1, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsNWidgets(3));
    });

    testWidgets('6 items — 6 ReceiptCard', (tester) async {
      final receipts = List.generate(
        6,
        (i) => _makeReceipt(id: 'r$i', periodStart: DateTime(2026, 6 - i, 1)),
      );

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsNWidgets(6));
    });

    testWidgets('squelette loading — aucune ReceiptCard', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(body: ReceiptsCardView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: _appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ReceiptCard), findsNothing);
    });

    testWidgets('pill "Émise" affiché sur card sans paiement', (tester) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.text('Émise'), findsOneWidget);
    });

    testWidgets('période "Mars 2026" affichée pour periodStart 2026-03-01', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      expect(find.text('Mars 2026'), findsOneWidget);
    });
  });

  group('ReceiptsCardView — couleur d\'identité du bien (FEAT-057)', () {
    testWidgets('propertyColorKey fourni → chaque carte a un liseré coloré', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
        _makeReceipt(id: 'r2', periodStart: DateTime(2026, 2, 1)),
      ];

      await tester.pumpWidget(
        _buildView(receipts, colorKey: PropertyColorKey.cobalt),
      );
      await tester.pumpAndSettle();

      final cards = tester.widgetList<SummaryCard>(find.byType(SummaryCard));
      expect(cards, hasLength(2));
      for (final card in cards) {
        expect(card.accentColor, isNotNull);
      }
    });

    testWidgets('propertyColorKey absent → liseré neutre (accentColor null)', (
      tester,
    ) async {
      final receipts = [
        _makeReceipt(id: 'r1', periodStart: DateTime(2026, 3, 1)),
      ];

      await tester.pumpWidget(_buildView(receipts));
      await tester.pumpAndSettle();

      final card = tester.widget<SummaryCard>(find.byType(SummaryCard));
      expect(card.accentColor, isNull);
    });
  });

  group('ReceiptsCardView — hauteur de cellule (mainAxisExtent 132)', () {
    testWidgets('pire cas desktop 1280 px — aucun overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final stale = Receipt(
        id: 'r-stale',
        landlordId: 'landlord-1',
        leaseId: 'lease-1',
        paymentIds: const ['pay-1'],
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        totalCents: 123456789,
        rentCents: 123000000,
        chargesCents: 456789,
        documentType: DocumentType.quittance,
        pdfPath: 'l-1/r-stale.pdf',
        isVoided: false,
        isStale: true,
        generatedAt: DateTime(2026, 9, 5),
        createdAt: DateTime(2026, 9, 5),
        sentAt: DateTime(2026, 9, 6),
        sentToEmail: 'un.prenom.tres.long@un-domaine-tres-long-example.com',
      );
      final voided = Receipt(
        id: 'r-voided',
        landlordId: 'landlord-1',
        leaseId: 'lease-1',
        paymentIds: const ['pay-1'],
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        totalCents: 123456789,
        rentCents: 123000000,
        chargesCents: 456789,
        documentType: DocumentType.quittance,
        pdfPath: 'l-1/r-voided.pdf',
        isVoided: true,
        voidedAt: DateTime(2026, 8, 10),
        voidedReason:
            'Motif d\'annulation très long qui dépasse largement la largeur '
            'disponible de la carte et doit être tronqué proprement sans '
            'provoquer le moindre débordement de mise en page',
        isStale: false,
        generatedAt: DateTime(2026, 8, 5),
        createdAt: DateTime(2026, 8, 5),
      );

      await tester.pumpWidget(_buildView([stale, voided]));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Tests unitaires de [receiptStatusPill] et helpers associés.
///
/// Couvre les 5 statuts effectifs + [receiptSecondaryLine].
///
/// [receiptStatusPill] et [receiptSecondaryLine] exigent désormais un
/// [BuildContext] pour résoudre les libellés via `AppLocalizations`
/// (FEAT-043) — on capture leur résultat depuis un harnais [MaterialApp]
/// localisé en français, comme `test/widget/lease_status_mapper_test.dart`.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipt_status_mapper.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  bool isVoided = false,
  bool isStale = false,
  List<String> paymentIds = const [],
  DateTime? sentAt,
  String? sentToEmail,
  DateTime? voidedAt,
  String? voidedReason,
}) => Receipt(
  id: 'r-1',
  landlordId: 'l-1',
  leaseId: 'lease-1',
  paymentIds: paymentIds,
  periodStart: DateTime(2026, 3, 1),
  periodEnd: DateTime(2026, 3, 31),
  totalCents: 120000,
  rentCents: 110000,
  chargesCents: 10000,
  documentType: DocumentType.quittance,
  pdfPath: 'l-1/r-1.pdf',
  isVoided: isVoided,
  voidedAt: voidedAt,
  voidedReason: voidedReason,
  isStale: isStale,
  generatedAt: DateTime(2026, 3, 4),
  createdAt: DateTime(2026, 3, 4),
  sentAt: sentAt,
  sentToEmail: sentToEmail,
);

ReceiptStatusPillData? _capturedPill;
String? _capturedLine;

/// Harnais localisé (FR) capturant le résultat de [receiptStatusPill] et
/// [receiptSecondaryLine] pour la [receipt] donnée.
Widget _harness(Receipt receipt) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Builder(
    builder: (context) {
      _capturedPill = receiptStatusPill(context, receipt);
      _capturedLine = receiptSecondaryLine(context, receipt);
      return const SizedBox.shrink();
    },
  ),
);

// ---------------------------------------------------------------------------
// Tests receiptStatusPill
// ---------------------------------------------------------------------------

void main() {
  group('receiptStatusPill', () {
    testWidgets('isVoided → danger "Annulée"', (tester) async {
      await tester.pumpWidget(_harness(_makeReceipt(isVoided: true)));
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.danger);
      expect(pill.label, 'Annulée');
    });

    testWidgets('isStale (non voided) → warning "Périmée"', (tester) async {
      await tester.pumpWidget(_harness(_makeReceipt(isStale: true)));
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.warning);
      expect(pill.label, 'Périmée');
    });

    testWidgets('hasBeenShared (non voided, non stale) → success "Envoyée"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _makeReceipt(
            paymentIds: ['pay-1'],
            sentAt: DateTime(2026, 3, 5),
            sentToEmail: 'test@example.com',
          ),
        ),
      );
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.success);
      expect(pill.label, 'Envoyée');
    });

    testWidgets('paymentIds non vide, non partagée → info "Payée"', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_makeReceipt(paymentIds: ['pay-1'])));
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.info);
      expect(pill.label, 'Payée');
    });

    testWidgets('aucun paiement, non partagée → info "Émise"', (tester) async {
      await tester.pumpWidget(_harness(_makeReceipt()));
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.info);
      expect(pill.label, 'Émise');
    });

    testWidgets('isVoided prioritaire sur isStale → danger "Annulée"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_makeReceipt(isVoided: true, isStale: true)),
      );
      final pill = _capturedPill!;
      expect(pill.tone, StatusPillTone.danger);
      expect(pill.label, 'Annulée');
    });
  });

  // ---------------------------------------------------------------------------
  // Tests receiptSecondaryLine
  // ---------------------------------------------------------------------------

  group('receiptSecondaryLine', () {
    testWidgets('voided → "Annulée le DD/MM"', (tester) async {
      await tester.pumpWidget(
        _harness(_makeReceipt(isVoided: true, voidedAt: DateTime(2026, 3, 6))),
      );
      final line = _capturedLine!;
      expect(line, contains('Annulée le 06/03'));
    });

    testWidgets('voided sans voidedAt → utilise generatedAt', (tester) async {
      await tester.pumpWidget(_harness(_makeReceipt(isVoided: true)));
      final line = _capturedLine!;
      expect(line, startsWith('Annulée le'));
    });

    testWidgets(
      'paid + sent → "Payée le DD/MM · Partagée le DD/MM à email masqué"',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            _makeReceipt(
              paymentIds: ['pay-1'],
              sentAt: DateTime(2026, 3, 5),
              sentToEmail: 'marie@example.com',
            ),
          ),
        );
        final line = _capturedLine!;
        expect(line, contains('Payée le'));
        expect(line, contains('Partagée le 05/03'));
        expect(line, contains('m***@example.com'));
      },
    );

    testWidgets('paid non partagée → "Payée le DD/MM"', (tester) async {
      await tester.pumpWidget(_harness(_makeReceipt(paymentIds: ['pay-1'])));
      final line = _capturedLine!;
      expect(line, startsWith('Payée le'));
      expect(line, isNot(contains('Partagée')));
    });

    testWidgets('émise (aucun paiement, non partagée) → "Émise le DD/MM"', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_makeReceipt()));
      final line = _capturedLine!;
      expect(line, startsWith('Émise le'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests receiptPeriodMonthYear
  // ---------------------------------------------------------------------------

  group('receiptPeriodMonthYear', () {
    setUpAll(initializeDateFormatting);

    test('français : capitalise le premier caractère du mois', () {
      final r = _makeReceipt();
      // Mois de mars 2026.
      expect(receiptPeriodMonthYear(r, 'fr'), 'Mars 2026');
    });

    test('anglais : mois en anglais (recette iOS 27, #197)', () {
      final r = _makeReceipt();
      expect(receiptPeriodMonthYear(r, 'en'), 'March 2026');
    });
  });
}

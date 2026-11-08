/// Tests "golden-free" de [renderReceiptPdf] — champ `notes` (FEAT-029 V1.1).
///
/// Même limite que `charge_regularization_pdf_renderer_test.dart` : le
/// package `pdf` ne permet pas l'extraction de texte, donc ce test vérifie
/// la robustesse du renderer (pas de crash) avec/sans motif renseigné,
/// plutôt qu'une assertion sur le contenu textuel exact du PDF.
library;

import 'package:easyrent/features/receipts/data/receipt_pdf_renderer.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptPdfData _makeData({String? notes}) => ReceiptPdfData(
  receiptId: 'r-123456789',
  documentType: DocumentType.quittance,
  landlordFullName: 'Marie Martin',
  landlordAddress: '1 rue de Paris, 75001 Paris',
  tenantFullName: 'Jean Dupont',
  propertyAddress: '2 rue de Lyon, 69001 Lyon',
  periodStart: DateTime(2026, 3, 1),
  periodEnd: DateTime(2026, 3, 31),
  rentCents: 85000,
  chargesCents: 5000,
  totalCents: 90000,
  lastPaidAt: DateTime(2026, 3, 5),
  generatedAt: DateTime(2026, 4, 1),
  notes: notes,
);

void main() {
  // Le renderer charge la police EB Garamond embarquée via `rootBundle`
  // (cf. `PdfBrandFonts`) — nécessite le binding Flutter Test initialisé.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('renderReceiptPdf — champ notes (FEAT-029 V1.1)', () {
    test('notes null → PDF généré sans exception', () async {
      final bytes = await renderReceiptPdf(_makeData());
      expect(bytes, isNotEmpty);
    });

    test('notes vide → PDF généré sans exception', () async {
      final bytes = await renderReceiptPdf(_makeData(notes: ''));
      expect(bytes, isNotEmpty);
    });

    test(
      'notes composées uniquement d\'espaces → PDF généré sans exception',
      () async {
        final bytes = await renderReceiptPdf(_makeData(notes: '   '));
        expect(bytes, isNotEmpty);
      },
    );

    test('notes renseignées (motif régularisation) → PDF plus volumineux '
        'que sans motif (contenu réellement injecté)', () async {
      final withoutNotes = await renderReceiptPdf(_makeData());
      final withNotes = await renderReceiptPdf(
        _makeData(
          notes:
              'Régularisation ascenseur T2 2026 — appel de fonds syndic '
              'exceptionnel refacturé au locataire selon décompte joint',
        ),
      );
      expect(withNotes.length, greaterThan(withoutNotes.length));
    });

    test('notes avec caractères spéciaux et accents ne lève pas '
        'd\'exception', () async {
      final bytes = await renderReceiptPdf(
        _makeData(notes: 'Régularisation « charges 2025 » — 1/2 mois'),
      );
      expect(bytes, isNotEmpty);
    });
  });
}

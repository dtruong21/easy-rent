// Génération PDF des quittances de loyer côté client (FEAT-019).
//
// Conforme à la loi du 6 juillet 1989, art. 21. Port Dart du layout
// précédemment en pdf-lib (Cloud Function) qui a été retiré pour économiser
// du Storage + Cloud Function bandwidth. La preuve légale reste le doc
// Firestore `receipts/{id}` immuable — le PDF n'est qu'une présentation
// visuelle générée à la demande à partir des denorms.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/french_date.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/pdf_brand_fonts.dart';
import '../domain/document_type.dart';

/// Snapshot des données nécessaires pour rendre une quittance.
///
/// Construit à partir du doc Firestore `receipts/{id}` (denorms immutables
/// posées par la Cloud Function `generateReceipt` au moment de l'émission).
class ReceiptPdfData {
  const ReceiptPdfData({
    required this.receiptId,
    required this.documentType,
    required this.landlordFullName,
    required this.landlordAddress,
    required this.tenantFullName,
    required this.propertyAddress,
    required this.periodStart,
    required this.periodEnd,
    required this.rentCents,
    required this.chargesCents,
    required this.totalCents,
    required this.lastPaidAt,
    required this.generatedAt,
    this.notes,
  });

  final String receiptId;
  final DocumentType documentType;
  final String landlordFullName;
  final String landlordAddress;
  final String tenantFullName;
  final String propertyAddress;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int rentCents;
  final int chargesCents;
  final int totalCents;
  final DateTime lastPaidAt;
  final DateTime generatedAt;

  /// Motif/notes du (des) paiement(s) source (FEAT-029 V1.1), agrégé côté
  /// client — le doc Firestore `receipts/{id}` ne porte pas ce champ (posé
  /// par la CF `generateReceipt`, hors scope de cette story). `null` ou vide
  /// si aucun paiement source ne porte de note.
  final String? notes;
}

/// Rend le PDF d'une quittance (A4 portrait, EB Garamond embarquée — cf.
/// [PdfBrandFonts] pour la justification et le sous-ensemblage du glyphset).
Future<Uint8List> renderReceiptPdf(ReceiptPdfData d) async {
  final doc = pw.Document(theme: await PdfBrandFonts.theme());

  final title = d.documentType == DocumentType.quittance
      ? 'QUITTANCE DE LOYER'
      : 'REÇU DE PAIEMENT';

  final isQuittance = d.documentType == DocumentType.quittance;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(50),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 1. Header
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            d.landlordFullName,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            d.landlordAddress,
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColor.fromInt(0xFF4D4D4D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Text(
                      'Fait le ${FrenchDate.format(d.generatedAt)}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColor.fromInt(0xFF4D4D4D),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 30),

                // 2. Title
                pw.Center(
                  child: pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Loyer de ${_monthYearFr(d.periodStart)}',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColor.fromInt(0xFF4D4D4D),
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 12),

                // 3. Tenant
                _section(label: 'Locataire :', value: d.tenantFullName),
                pw.SizedBox(height: 10),

                // 4. Property
                _section(label: 'Logement :', value: d.propertyAddress),
                pw.SizedBox(height: 10),

                // 5. Period
                _section(
                  label: 'Période concernée :',
                  value:
                      'du ${FrenchDate.format(d.periodStart)} au ${FrenchDate.format(d.periodEnd)}',
                ),

                // 5bis. Motif (FEAT-029 V1.1) — uniquement si renseigné.
                if (d.notes != null && d.notes!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  _section(label: 'Motif :', value: d.notes!.trim()),
                ],
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 12),

                // 6. Financial
                pw.Text(
                  'Détail du paiement :',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                _row(
                  label: 'Loyer hors charges',
                  value: MoneyFormat.formatEurosFromCents(d.rentCents),
                ),
                _row(
                  label: 'Charges',
                  value: MoneyFormat.formatEurosFromCents(d.chargesCents),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                _row(
                  label: 'Total reçu',
                  value: MoneyFormat.formatEurosFromCents(d.totalCents),
                  bold: true,
                  fontSize: 11,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Date du paiement : ${FrenchDate.format(d.lastPaidAt)}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromInt(0xFF4D4D4D),
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 18),

                // 7. Legal
                if (isQuittance)
                  pw.Text(
                    'Je soussigné(e) ${d.landlordFullName}, reconnais avoir reçu '
                    'de ${d.tenantFullName} la somme indiquée ci-dessus, pour '
                    'quittance et solde de tout compte pour la période susvisée.',
                    style: const pw.TextStyle(fontSize: 10),
                  )
                else ...[
                  pw.Text(
                    'Je soussigné(e) ${d.landlordFullName}, reconnais avoir reçu '
                    'de ${d.tenantFullName} la somme indiquée ci-dessus.',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Ce reçu ne libère pas le locataire du solde dû pour la '
                    'période concernée.',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFCC1A1A),
                    ),
                  ),
                ],
                pw.SizedBox(height: 24),

                // 8. Signature
                pw.Text(
                  'Fait le ${FrenchDate.format(d.generatedAt)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 30),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Signature du bailleur :',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF4D4D4D),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        d.landlordFullName,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 9. Footer (bottom)
            pw.Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: pw.Text(
                      'Réf. BAI-'
                      '${d.receiptId.substring(0, d.receiptId.length < 8 ? d.receiptId.length : 8).toUpperCase()}'
                      '  -  Émis par Baillan.  -  Loi du 6 juillet 1989',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColor.fromInt(0xFF999999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _section({required String label, required String value}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 10),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ),
    ],
  );
}

pw.Widget _row({
  required String label,
  required String value,
  bool bold = false,
  double fontSize = 10,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: bold ? PdfColors.black : const PdfColor.fromInt(0xFF4D4D4D),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

const _monthsFr = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _monthYearFr(DateTime d) => '${_monthsFr[d.month - 1]} ${d.year}';

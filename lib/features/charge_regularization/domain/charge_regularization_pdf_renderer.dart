// Génération PDF de l'avis de régularisation annuelle des charges, côté
// client (FEAT-029 V1.2 — bail nu uniquement, art. 23 loi du 6 juillet 1989
// + décret n°87-713).
//
// Port du style de `receipts/data/receipt_pdf_renderer.dart` (même
// bibliothèque `pdf`, même formatage FR). Contrairement à une quittance, ce
// document n'est PAS archivé comme `document`/`receipt` Firestore en V1 —
// il est généré à la volée à partir de données saisies et partagé
// directement (Web Share), voir commentaire détaillé dans
// `application/charge_statement_finalize_controller.dart` (flow de
// partage général).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/french_date.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/pdf_brand_fonts.dart';
import 'charge_regularization_balance.dart';
import 'charge_statement.dart';

/// Snapshot des données nécessaires pour rendre l'avis de régularisation.
class ChargeRegularizationPdfData {
  const ChargeRegularizationPdfData({
    required this.landlordFullName,
    required this.landlordAddress,
    required this.tenantFullName,
    required this.propertyAddress,
    required this.balance,
    required this.generatedAt,
  });

  final String landlordFullName;
  final String landlordAddress;
  final String tenantFullName;
  final String propertyAddress;
  final ChargeRegularizationBalance balance;
  final DateTime generatedAt;

  /// Construit les données PDF à partir d'un décompte figé (FEAT-033) — le
  /// PDF re-rendu est identique à celui émis lors de la finalisation, car
  /// entièrement dérivé des champs immuables de [s] (aucune source externe,
  /// aucune re-synchronisation).
  factory ChargeRegularizationPdfData.fromStatement(ChargeStatement s) {
    return ChargeRegularizationPdfData(
      landlordFullName: s.landlordFullName,
      landlordAddress: s.landlordAddress,
      tenantFullName: s.tenantFullName,
      propertyAddress: s.propertyAddress,
      balance: ChargeRegularizationBalance(
        periodStart: s.periodStart,
        periodEnd: s.periodEnd,
        provisionsCollectedCents: s.provisionsCollectedCents,
        actualExpensesCents: s.actualExpensesCents,
      ),
      generatedAt: s.createdAt,
    );
  }
}

/// Rend le PDF de l'avis de régularisation (A4 portrait, EB Garamond
/// embarquée — cohérent avec les quittances, cf. [PdfBrandFonts]).
Future<Uint8List> renderChargeRegularizationPdf(
  ChargeRegularizationPdfData d,
) async {
  final doc = pw.Document(theme: await PdfBrandFonts.theme());
  final balance = d.balance;

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
                    'AVIS DE RÉGULARISATION DES CHARGES',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Période du ${FrenchDate.format(balance.periodStart)} '
                    'au ${FrenchDate.format(balance.periodEnd)}',
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
                  label: 'Période de référence :',
                  value:
                      'du ${FrenchDate.format(balance.periodStart)} au '
                      '${FrenchDate.format(balance.periodEnd)}',
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 12),

                // 6. Financial detail
                pw.Text(
                  'Décompte :',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                _row(
                  label: 'Total des provisions encaissées',
                  value: MoneyFormat.formatEurosFromCents(
                    balance.provisionsCollectedCents,
                  ),
                ),
                _row(
                  label: 'Total des dépenses réelles justifiées',
                  value: MoneyFormat.formatEurosFromCents(
                    balance.actualExpensesCents,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                _row(
                  label: 'Solde (${balance.labelFr})',
                  value: MoneyFormat.formatEurosFromCents(
                    balance.balanceAbsCents,
                  ),
                  bold: true,
                  fontSize: 12,
                ),
                pw.SizedBox(height: 18),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 18),

                // 7. Legal
                pw.Text(
                  'Ce document constitue le justificatif de la '
                  'régularisation annuelle des charges récupérables, '
                  'établi conformément à l\'article 23 de la loi n 89-462 '
                  'du 6 juillet 1989 et au décret n 87-713 du 26 août '
                  '1987. Seules les charges de nature récupérable ont '
                  'été prises en compte dans ce décompte.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
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
                      'Émis par Baillan.  -  Loi du 6 juillet 1989, art. 23',
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
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: bold
                  ? PdfColors.black
                  : const PdfColor.fromInt(0xFF4D4D4D),
            ),
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

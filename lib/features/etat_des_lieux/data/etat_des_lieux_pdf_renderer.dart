// Génération PDF de l'état des lieux côté client (FEAT-037), conforme au
// décret n°2016-382 du 30 mars 2016 fixant le contenu-type de l'état des
// lieux (loi du 6 juillet 1989, art. 3-2).
//
// Port du style de `receipts/data/receipt_pdf_renderer.dart` (même
// bibliothèque `pdf`, même police EB Garamond). Contrairement à la quittance,
// la preuve légale est le doc Firestore `etat_des_lieux/{id}` immuable (posé
// par la Cloud Function `createEtatDesLieux`, cf. task 3) — le PDF n'est
// qu'une présentation visuelle générée à la demande à partir de ces denorms.
//
// Un EDL peut compter de nombreuses pièces/éléments : `pw.MultiPage` (et non
// `pw.Page`) gère la pagination automatique plutôt qu'un layout figé sur une
// seule page qui débordait silencieusement (texte tronqué hors de la zone
// imprimable).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/french_date.dart';
import '../../../core/utils/pdf_brand_fonts.dart';
import '../domain/edl_enums.dart';
import '../domain/etat_des_lieux.dart';

/// Rend le PDF d'un état des lieux (A4 portrait, EB Garamond embarquée —
/// cf. [PdfBrandFonts]).
Future<Uint8List> renderEtatDesLieuxPdf(EtatDesLieux edl) async {
  final doc = pw.Document(theme: await PdfBrandFonts.theme());

  final title = edl.type == EtatDesLieuxType.entree
      ? "État des lieux d'entrée"
      : 'État des lieux de sortie';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(50),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                title,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromInt(0xFF999999),
                ),
              ),
            ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Émis par Baillan.  -  Loi du 6 juillet 1989, art. 3-2  -  '
              'Décret n°2016-382',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColor.fromInt(0xFF999999),
              ),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColor.fromInt(0xFF999999),
              ),
            ),
          ],
        ),
      ),
      build: (context) => [
        // 1. En-tête : titre, date, adresse, parties.
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'Établi le ${FrenchDate.format(edl.date)}',
            style: const pw.TextStyle(
              fontSize: 12,
              color: PdfColor.fromInt(0xFF4D4D4D),
            ),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 12),

        _section(label: 'Logement :', value: edl.propertyAddress),
        pw.SizedBox(height: 10),
        _section(label: 'Bailleur :', value: edl.landlordFullName),
        pw.SizedBox(height: 10),
        _section(label: 'Locataire :', value: edl.tenantFullName),
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 12),

        // 2. Par pièce : un tableau élément | état | commentaire.
        pw.Text(
          'État des pièces',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        for (final room in edl.rooms) ...[
          pw.Text(
            room.name,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: const ['Élément', 'État', 'Commentaire'],
            data: [
              for (final element in room.elements)
                [
                  element.name,
                  _conditionLabelFr(element.condition),
                  element.comment ?? '',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF4D4D4D),
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(3),
            },
          ),
          pw.SizedBox(height: 14),
        ],

        // 3. Relevés compteurs (uniquement les non-null).
        if (_hasMeterReadings(edl.meterReadings)) ...[
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 12),
          pw.Text(
            'Relevés des compteurs',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (edl.meterReadings.waterIndex != null)
            _row(label: 'Eau', value: edl.meterReadings.waterIndex!),
          if (edl.meterReadings.electricityIndex != null)
            _row(
              label: 'Électricité',
              value: edl.meterReadings.electricityIndex!,
            ),
          if (edl.meterReadings.gasIndex != null)
            _row(label: 'Gaz', value: edl.meterReadings.gasIndex!),
          pw.SizedBox(height: 16),
        ],

        // 4. Nombre de clés remises.
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 12),
        _row(label: 'Nombre de clés remises', value: '${edl.keysCount}'),
        pw.SizedBox(height: 16),

        // 5. Commentaire général (si présent).
        if (edl.generalComment != null &&
            edl.generalComment!.trim().isNotEmpty) ...[
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 12),
          _section(
            label: 'Commentaire général :',
            value: edl.generalComment!.trim(),
          ),
          pw.SizedBox(height: 16),
        ],

        pw.SizedBox(height: 12),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 24),

        // 6. Blocs signature.
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _signatureBlock('Le bailleur', edl)),
            pw.SizedBox(width: 30),
            pw.Expanded(child: _signatureBlock('Le locataire', edl)),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _signatureBlock(String label, EtatDesLieux edl) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Fait à ................................, '
        'le ${FrenchDate.format(edl.date)}',
        style: const pw.TextStyle(
          fontSize: 9,
          color: PdfColor.fromInt(0xFF4D4D4D),
        ),
      ),
      pw.SizedBox(height: 30),
      pw.Text('Signature :', style: const pw.TextStyle(fontSize: 9)),
    ],
  );
}

bool _hasMeterReadings(EdlMeterReadings readings) =>
    readings.waterIndex != null ||
    readings.electricityIndex != null ||
    readings.gasIndex != null;

String _conditionLabelFr(EdlCondition condition) {
  switch (condition) {
    case EdlCondition.neuf:
      return 'Neuf';
    case EdlCondition.bon:
      return 'Bon';
    case EdlCondition.moyen:
      return 'Moyen';
    case EdlCondition.mauvais:
      return 'Mauvais';
  }
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

pw.Widget _row({required String label, required String value}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColor.fromInt(0xFF4D4D4D),
          ),
        ),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );
}

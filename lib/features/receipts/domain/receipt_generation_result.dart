import 'document_type.dart';

/// Résultat retourné par la Cloud Function `generateReceipt`.
///
/// Contient les informations nécessaires pour afficher le dialog de prévisualisation
/// et ouvrir le PDF.
///
/// [pdfUrl] : URL signée valide 5 min — à utiliser immédiatement pour
/// ouvrir le PDF dans un nouvel onglet. Ne pas stocker.
class ReceiptGenerationResult {
  const ReceiptGenerationResult({
    required this.receiptId,
    required this.pdfUrl,
    required this.documentType,
    required this.totalCents,
    required this.periodStart,
    required this.periodEnd,
  });

  /// Identifiant de la quittance créée côté Firestore.
  final String receiptId;

  /// URL signée (5 min) pour accéder au PDF.
  final String pdfUrl;

  /// Type de document généré selon le montant total vs loyer dû.
  final DocumentType documentType;

  /// Montant total en centimes.
  final int totalCents;

  /// Début de période couverte.
  final DateTime periodStart;

  /// Fin de période couverte.
  final DateTime periodEnd;

  factory ReceiptGenerationResult.fromJson(Map<String, dynamic> json) {
    return ReceiptGenerationResult(
      receiptId: json['receipt_id'] as String,
      pdfUrl: json['pdf_url'] as String,
      documentType: DocumentType.fromSql(json['document_type'] as String),
      totalCents: json['total_cents'] as int,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
    );
  }
}

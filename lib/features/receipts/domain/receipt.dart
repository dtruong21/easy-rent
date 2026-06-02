// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/french_date.dart';
import '../../../core/utils/money_format.dart';
import 'document_type.dart';

part 'receipt.freezed.dart';
part 'receipt.g.dart';

/// Modèle immutable d'une quittance de loyer.
///
/// Mappé directement sur la table `receipts` (public + dev).
/// Document immuable (pas d'`updated_at`) — seuls [isVoided] et [isStale]
/// peuvent changer (via RPC `void_receipt` et trigger `tr_03_*`).
///
/// Les montants sont en centimes (entiers) — jamais de `double`.
/// Les dates [periodStart], [periodEnd] sont sérialisées en `YYYY-MM-DD`.
@freezed
class Receipt with _$Receipt {
  const factory Receipt({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(
      name: 'payment_ids',
      fromJson: _stringListFromJson,
      toJson: _stringListToJson,
    )
    required List<String> paymentIds,
    @JsonKey(name: 'period_start', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime periodStart,
    @JsonKey(name: 'period_end', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime periodEnd,
    @JsonKey(name: 'total_cents') required int totalCents,
    @JsonKey(name: 'rent_cents') required int rentCents,
    @JsonKey(name: 'charges_cents') required int chargesCents,
    @JsonKey(
      name: 'document_type',
      fromJson: _documentTypeFromJson,
      toJson: _documentTypeToJson,
    )
    required DocumentType documentType,
    @JsonKey(name: 'pdf_path') required String pdfPath,
    @JsonKey(name: 'is_voided') required bool isVoided,
    @JsonKey(name: 'voided_at') DateTime? voidedAt,
    @JsonKey(name: 'voided_reason') String? voidedReason,
    @JsonKey(name: 'is_stale') required bool isStale,
    @JsonKey(name: 'generated_at') required DateTime generatedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'sent_at') DateTime? sentAt,
    @JsonKey(name: 'sent_to_email') String? sentToEmail,
  }) = _Receipt;

  factory Receipt.fromJson(Map<String, dynamic> json) =>
      _$ReceiptFromJson(json);
}

// ---------------------------------------------------------------------------
// Helpers JSON privés
// ---------------------------------------------------------------------------

DateTime _dateFromJson(dynamic value) {
  if (value is String) {
    return DateTime.parse(value);
  }
  throw ArgumentError('Expected String for date, got ${value.runtimeType}');
}

String _dateToJson(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<String> _stringListFromJson(dynamic value) {
  if (value is List) {
    return value.map((e) => e as String).toList();
  }
  throw ArgumentError(
    'Expected List<dynamic> for payment_ids, got ${value.runtimeType}',
  );
}

List<String> _stringListToJson(List<String> list) => list;

DocumentType _documentTypeFromJson(dynamic value) =>
    DocumentType.fromSql(value as String);

String _documentTypeToJson(DocumentType type) => type.sqlValue;

// ---------------------------------------------------------------------------
// Extension — getters calculés (hors freezed pour éviter le codegen)
// ---------------------------------------------------------------------------

/// Getters utilitaires sur une quittance.
extension ReceiptExtension on Receipt {
  /// Montant total formaté en euros (ex: "1 234,56 €").
  String get totalEuros => MoneyFormat.formatEurosFromCents(totalCents);

  /// Libellé de période formaté en FR (ex: "01/01/2026 – 31/01/2026").
  String get periodLabel =>
      '${FrenchDate.format(periodStart)} – ${FrenchDate.format(periodEnd)}';

  /// Vrai si la quittance a déjà été envoyée par email.
  bool get hasBeenSent => sentAt != null;

  /// Date d'envoi formatée en FR (ex: "01/06/2026"), ou null si jamais envoyée.
  String? get sentAtLabel => sentAt != null ? FrenchDate.format(sentAt!) : null;

  /// Email de destination masqué pour l'affichage RGPD
  /// (ex: "j***@example.com" — premier caractère + 3 étoiles + @domaine).
  ///
  /// Retourne null si [sentToEmail] est null.
  String? get maskedSentToEmail {
    final email = sentToEmail;
    if (email == null) return null;
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return '***';
    final local = email.substring(0, atIndex);
    final domain = email.substring(atIndex); // includes '@'
    final firstChar = local.isNotEmpty ? local[0] : '';
    return '$firstChar***$domain';
  }
}

// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'payment_method.dart';

part 'payment.freezed.dart';
part 'payment.g.dart';

/// Modèle immutable d'un paiement de loyer.
///
/// Mappé directement sur la table `payments` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées par
/// les triggers Supabase — ne jamais les inclure dans un payload INSERT/UPDATE.
///
/// [landlordId] : FK vers `landlords.id`. Passé explicitement dans l'INSERT
/// car la policy `payments_insert_own` exige `landlord_id = auth.uid()`.
///
/// Les dates [periodStart], [periodEnd] et [paidAt] sont sérialisées en
/// `YYYY-MM-DD` côté Postgres (`date`). Les helpers `_dateFromJson` /
/// `_dateToJson` gèrent cette conversion.
///
/// Les montants [rentAmountCents] et [chargesAmountCents] sont en centimes
/// (entiers) — jamais de `double` dans un payload.
@freezed
class Payment with _$Payment {
  const factory Payment({
    required String id,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'period_start', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime periodStart,
    @JsonKey(name: 'period_end', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime periodEnd,
    @JsonKey(name: 'paid_at', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime paidAt,
    @JsonKey(name: 'rent_amount_cents') required int rentAmountCents,
    @JsonKey(name: 'charges_amount_cents') required int chargesAmountCents,
    @JsonKey(
      name: 'payment_method',
      fromJson: _methodFromJson,
      toJson: _methodToJson,
    )
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Payment;

  factory Payment.fromJson(Map<String, dynamic> json) =>
      _$PaymentFromJson(json);
}

// ---------------------------------------------------------------------------
// Helpers JSON privés — date Postgres `YYYY-MM-DD` ↔ DateTime Dart
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

PaymentMethod _methodFromJson(dynamic value) =>
    PaymentMethod.fromSql(value as String);

String _methodToJson(PaymentMethod method) => method.sqlValue;

// ---------------------------------------------------------------------------
// Extension — getters calculés (non freezed pour éviter le codegen)
// ---------------------------------------------------------------------------

/// Getters utilitaires sur un paiement.
extension PaymentExtension on Payment {
  /// Montant total (loyer HC + charges) en centimes.
  int get totalAmountCents => rentAmountCents + chargesAmountCents;
}

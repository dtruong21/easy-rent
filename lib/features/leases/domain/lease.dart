// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'lease_status.dart';

part 'lease.freezed.dart';
part 'lease.g.dart';

/// Modèle immutable d'un bail.
///
/// Mappé directement sur la table `leases` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées par
/// les triggers Supabase — ne jamais les inclure dans un payload INSERT/UPDATE.
///
/// [landlordId] : FK vers `landlords.id`. Ne pas l'envoyer dans un INSERT
/// depuis le client — la RLS (`leases_insert_own`) vérifie `= auth.uid()`.
///
/// Les dates [startDate] et [endDate] sont des `DateTime` côté Dart mais
/// sérialisées en `YYYY-MM-DD` côté Postgres (`date`). Les helpers
/// `_dateFromJson` / `_dateToJson` gèrent cette conversion.
///
/// Les montants [rentAmountCents] et [chargesAmountCents] sont en centimes
/// (entiers) — jamais de `double` dans un payload.
@freezed
class Lease with _$Lease {
  const factory Lease({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'property_id') required String propertyId,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'rent_amount_cents') required int rentAmountCents,
    @JsonKey(name: 'charges_amount_cents') required int chargesAmountCents,
    @JsonKey(name: 'start_date', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime startDate,
    @JsonKey(
      name: 'end_date',
      fromJson: _nullableDateFromJson,
      toJson: _nullableDateToJson,
    )
    DateTime? endDate,
    @JsonKey(name: 'status', fromJson: _statusFromJson, toJson: _statusToJson)
    required LeaseStatus status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Lease;

  factory Lease.fromJson(Map<String, dynamic> json) => _$LeaseFromJson(json);
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

DateTime? _nullableDateFromJson(dynamic value) {
  if (value == null) return null;
  return _dateFromJson(value);
}

String? _nullableDateToJson(DateTime? date) {
  if (date == null) return null;
  return _dateToJson(date);
}

LeaseStatus _statusFromJson(dynamic value) =>
    LeaseStatus.fromSql(value as String);

String _statusToJson(LeaseStatus status) => status.sqlValue;

// ---------------------------------------------------------------------------
// Extension — getters calculés (non freezed pour éviter le codegen)
// ---------------------------------------------------------------------------

/// Getters utilitaires sur un bail.
extension LeaseExtension on Lease {
  /// Loyer toutes charges comprises en centimes.
  int get totalAmountCents => rentAmountCents + chargesAmountCents;

  /// Vrai si le bail est actif et non archivé.
  bool get isActive => status == LeaseStatus.active && deletedAt == null;

  /// Vrai si le bail est clôturé (terminé).
  bool get isClosed => status == LeaseStatus.terminated;
}

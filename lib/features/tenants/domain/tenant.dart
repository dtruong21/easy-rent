// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tenant.freezed.dart';
part 'tenant.g.dart';

// Helpers JSON pour birth_date (utilisés par @JsonKey).
DateTime? _nullableDateFromJson(String? v) =>
    v == null ? null : DateTime.parse(v);
String? _nullableDateToJson(DateTime? v) => v == null
    ? null
    : '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';

/// Modèle immutable d'un locataire.
///
/// Mappé directement sur la table `tenants` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées
/// par les triggers Cloud Functions — ne jamais les inclure dans un payload de création/mise à jour.
///
/// [landlordId] : FK vers `landlords.id`. Ne pas l'envoyer dans un INSERT
/// depuis le client — les Firestore Rules vérifient `landlordId == request.auth.uid`.
@freezed
class Tenant with _$Tenant {
  const factory Tenant({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'first_name') required String firstName,
    @JsonKey(name: 'last_name') required String lastName,
    required String email,
    String? phone,
    // Champs enrichissement FEAT-014 Phase 2 — tous nullable (backward compat).
    @JsonKey(
      name: 'birth_date',
      fromJson: _nullableDateFromJson,
      toJson: _nullableDateToJson,
    )
    DateTime? birthDate,
    @JsonKey(name: 'birth_place') String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    @JsonKey(name: 'monthly_income_cents') int? monthlyIncomeCents,
    @JsonKey(name: 'previous_address') String? previousAddress,
    @JsonKey(name: 'guarantor_name') String? guarantorName,
    @JsonKey(name: 'guarantor_email') String? guarantorEmail,
    @JsonKey(name: 'guarantor_phone') String? guarantorPhone,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Tenant;

  factory Tenant.fromJson(Map<String, dynamic> json) => _$TenantFromJson(json);
}

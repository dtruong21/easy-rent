// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tenant.freezed.dart';
part 'tenant.g.dart';

/// Modèle immutable d'un locataire.
///
/// Mappé directement sur la table `tenants` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées
/// par les triggers Supabase — ne jamais les inclure dans un payload INSERT/UPDATE.
///
/// [landlordId] : FK vers `landlords.id`. Ne pas l'envoyer dans un INSERT
/// depuis le client — la RLS (`tenants_insert_own`) vérifie `= auth.uid()`.
///
/// Pas d'enum — tous les champs sont des scalaires (String, String?, DateTime).
@freezed
class Tenant with _$Tenant {
  const factory Tenant({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'first_name') required String firstName,
    @JsonKey(name: 'last_name') required String lastName,
    required String email,
    String? phone,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Tenant;

  factory Tenant.fromJson(Map<String, dynamic> json) => _$TenantFromJson(json);
}

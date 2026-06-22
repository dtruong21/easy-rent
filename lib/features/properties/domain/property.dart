// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'heating_type.dart';
import 'property_type.dart';

part 'property.freezed.dart';
part 'property.g.dart';

// Helpers JSON pour PropertyType (utilisés par @JsonKey).
PropertyType _typeFromJson(String value) => PropertyType.fromSql(value);
String _typeToJson(PropertyType type) => type.sqlValue;

// Helpers JSON pour HeatingType (utilisés par @JsonKey).
HeatingType? _heatingFromJson(String? v) => HeatingType.fromSql(v);
String? _heatingToJson(HeatingType? v) => v?.sqlValue;

/// Modèle immutable d'un bien immobilier.
///
/// Mappé directement sur la table `properties` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées
/// par les triggers Supabase — ne jamais les inclure dans un payload INSERT/UPDATE.
///
/// [landlordId] : FK vers `landlords.id`. Ne pas l'envoyer dans un INSERT
/// depuis le client — la RLS (`properties_insert_own`) vérifie `= auth.uid()`.
@freezed
class Property with _$Property {
  const factory Property({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    required String name,
    required String address,
    @JsonKey(fromJson: _typeFromJson, toJson: _typeToJson)
    required PropertyType type,
    @JsonKey(name: 'surface_m2') double? surfaceM2,
    @JsonKey(name: 'postal_code') String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    @JsonKey(name: 'has_elevator') @Default(false) bool hasElevator,
    @Default(false) bool furnished,
    @JsonKey(
      name: 'heating_type',
      fromJson: _heatingFromJson,
      toJson: _heatingToJson,
    )
    HeatingType? heatingType,
    @JsonKey(name: 'dpe_letter') String? dpeLetter,
    @JsonKey(name: 'dpe_value_kwh_m2_year') int? dpeValueKwhM2Year,
    @JsonKey(name: 'ges_letter') String? gesLetter,
    @JsonKey(name: 'construction_year') int? constructionYear,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Property;

  factory Property.fromJson(Map<String, dynamic> json) =>
      _$PropertyFromJson(json);
}

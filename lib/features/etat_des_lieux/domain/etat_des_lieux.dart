// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'edl_enums.dart';

part 'etat_des_lieux.freezed.dart';
part 'etat_des_lieux.g.dart';

EtatDesLieuxType _typeFromJson(String v) => EtatDesLieuxType.fromSql(v);
String _typeToJson(EtatDesLieuxType v) => v.sqlValue;
EdlCondition _condFromJson(String v) => EdlCondition.fromSql(v);
String _condToJson(EdlCondition v) => v.sqlValue;

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

@freezed
class EtatDesLieux with _$EtatDesLieux {
  const factory EtatDesLieux({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(name: 'type', fromJson: _typeFromJson, toJson: _typeToJson)
    required EtatDesLieuxType type,
    @JsonKey(fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime date,
    @JsonKey(name: 'property_address') required String propertyAddress,
    @JsonKey(name: 'landlord_full_name') required String landlordFullName,
    @JsonKey(name: 'tenant_full_name') required String tenantFullName,
    required List<EdlRoom> rooms,
    @JsonKey(name: 'meter_readings') required EdlMeterReadings meterReadings,
    @JsonKey(name: 'keys_count') required int keysCount,
    @JsonKey(name: 'general_comment') String? generalComment,
    @JsonKey(name: 'created_at', fromJson: _dateFromJson, toJson: _dateToJson)
    required DateTime createdAt,
  }) = _EtatDesLieux;

  factory EtatDesLieux.fromJson(Map<String, dynamic> json) =>
      _$EtatDesLieuxFromJson(json);
}

@freezed
class EdlRoom with _$EdlRoom {
  const factory EdlRoom({
    required String name,
    required List<EdlElement> elements,
  }) = _EdlRoom;

  factory EdlRoom.fromJson(Map<String, dynamic> json) =>
      _$EdlRoomFromJson(json);
}

@freezed
class EdlElement with _$EdlElement {
  const factory EdlElement({
    required String name,
    @JsonKey(fromJson: _condFromJson, toJson: _condToJson)
    required EdlCondition condition,
    String? comment,
  }) = _EdlElement;

  factory EdlElement.fromJson(Map<String, dynamic> json) =>
      _$EdlElementFromJson(json);
}

@freezed
class EdlMeterReadings with _$EdlMeterReadings {
  const factory EdlMeterReadings({
    @JsonKey(name: 'water_index') String? waterIndex,
    @JsonKey(name: 'electricity_index') String? electricityIndex,
    @JsonKey(name: 'gas_index') String? gasIndex,
  }) = _EdlMeterReadings;

  factory EdlMeterReadings.fromJson(Map<String, dynamic> json) =>
      _$EdlMeterReadingsFromJson(json);
}

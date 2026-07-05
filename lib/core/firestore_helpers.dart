// Helpers de conversion Firestore ↔ modèles freezed snake_case.
//
// Les modèles Dart (Property, Tenant, etc.) ont été générés avec
// `@JsonKey(name: 'snake_case')` pour matcher l'ancien schéma Postgres.
// Firestore stocke en camelCase (cf. docs/plans/FEAT-019-firestore-data-model.md).
// Ces helpers font le pont sans toucher aux modèles eux-mêmes.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Convertit une Map Firestore (camelCase + Timestamp) vers la forme JSON
/// snake_case attendue par `Model.fromJson(...)`.
///
/// - clés `camelCase` → `snake_case`
/// - `Timestamp` → ISO 8601 string (json_serializable parse via DateTime.parse)
/// - `id` ajouté/écrasé avec [docId] (les docId Firestore restent autoritatifs)
/// - `null` conservé
Map<String, dynamic> firestoreDocToSnakeJson(
  Map<String, dynamic> data, {
  required String docId,
}) {
  final out = <String, dynamic>{'id': docId};
  data.forEach((key, value) {
    final snakeKey = _camelToSnake(key);
    out[snakeKey] = _convertFirestoreValue(value);
  });
  return out;
}

/// Convertit une Map snake_case (payload modèle.toJson) vers la forme
/// camelCase attendue par Firestore.
///
/// - clés `snake_case` → `camelCase`
/// - `DateTime` → [Timestamp]
/// - dates ISO YYYY-MM-DD restent strings (jamais converties)
///   sauf si explicitement marquées DateTime
Map<String, dynamic> snakeJsonToFirestoreDoc(Map<String, dynamic> data) {
  final out = <String, dynamic>{};
  data.forEach((key, value) {
    if (key == 'id') return; // docId géré séparément
    final camelKey = _snakeToCamel(key);
    out[camelKey] = _convertToFirestoreValue(value);
  });
  return out;
}

String _camelToSnake(String s) =>
    s.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String _snakeToCamel(String s) =>
    s.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());

dynamic _convertFirestoreValue(dynamic value) {
  if (value is Timestamp) {
    return value.toDate().toUtc().toIso8601String();
  }
  if (value is Map<String, dynamic>) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      out[_camelToSnake(k)] = _convertFirestoreValue(v);
    });
    return out;
  }
  if (value is List) {
    return value.map(_convertFirestoreValue).toList();
  }
  return value;
}

dynamic _convertToFirestoreValue(dynamic value) {
  if (value is DateTime) {
    return Timestamp.fromDate(value.toUtc());
  }
  if (value is Map<String, dynamic>) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      out[_snakeToCamel(k)] = _convertToFirestoreValue(v);
    });
    return out;
  }
  if (value is List) {
    return value.map(_convertToFirestoreValue).toList();
  }
  return value;
}

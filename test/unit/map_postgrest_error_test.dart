import 'package:easyrent/core/utils/postgrest_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Construit un [PostgrestException] avec les champs minimaux requis.
PostgrestException _pge({required String code, required String message}) =>
    PostgrestException(code: code, message: message, details: '', hint: '');

void main() {
  group('mapPostgrestError', () {
    test('code 42501 → message droits', () {
      final msg = mapPostgrestError(
        _pge(code: '42501', message: 'permission denied'),
      );
      expect(msg.toLowerCase(), contains('droits'));
    });

    test('message "permission denied" → message droits', () {
      final msg = mapPostgrestError(
        _pge(code: '', message: 'Permission Denied by RLS'),
      );
      expect(msg.toLowerCase(), contains('droits'));
    });

    test('code 23514 avec "surface" → message surface', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation on surface_m2'),
      );
      expect(msg.toLowerCase(), contains('surface'));
    });

    test('code 23514 avec "type" → message type invalide', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation on type'),
      );
      expect(msg.toLowerCase(), contains('type'));
    });

    test('code 23514 sans champ connu → message générique invalide', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation'),
      );
      expect(msg, isNotEmpty);
    });

    test('code 23502 → champ obligatoire manquant', () {
      final msg = mapPostgrestError(
        _pge(code: '23502', message: 'not_null_violation'),
      );
      expect(msg.toLowerCase(), contains('obligatoire'));
    });

    test('message "network" → erreur réseau', () {
      final msg = mapPostgrestError(
        _pge(code: '', message: 'network error occurred'),
      );
      expect(msg.toLowerCase(), contains('réseau'));
    });

    test('message "timeout" → erreur réseau', () {
      final msg = mapPostgrestError(_pge(code: '', message: 'request timeout'));
      expect(msg.toLowerCase(), contains('réseau'));
    });

    test('erreur inconnue → message générique non vide', () {
      final msg = mapPostgrestError(
        _pge(code: '99999', message: 'some unknown error'),
      );
      expect(msg, isNotEmpty);
    });
  });
}

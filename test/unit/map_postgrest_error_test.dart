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

    // --- FEAT-006 enrichments -----------------------------------------------

    test('code P0002 → élément introuvable (RPC soft_delete cross-user)', () {
      final msg = mapPostgrestError(
        _pge(code: 'P0002', message: 'no data found'),
      );
      expect(msg.toLowerCase(), contains('introuvable'));
    });

    test('23514 + "Ownership mismatch" → message bail pas à toi', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'Ownership mismatch on lease_id'),
      );
      expect(msg.toLowerCase(), contains('bail'));
      expect(msg.toLowerCase(), contains('pas'));
    });

    test('23514 + "period_end" → date de fin > début', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation period_end_check'),
      );
      expect(msg.toLowerCase(), contains('fin'));
      expect(msg.toLowerCase(), contains('début'));
    });

    test('23514 + "rent_amount" → loyer positif', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation rent_amount_cents_check'),
      );
      expect(msg.toLowerCase(), contains('loyer'));
      expect(msg.toLowerCase(), contains('positif'));
    });

    test('23514 + "charges_amount" → charges non négatives', () {
      final msg = mapPostgrestError(
        _pge(
          code: '23514',
          message: 'check_violation charges_amount_cents_check',
        ),
      );
      expect(msg.toLowerCase(), contains('charges'));
      expect(msg.toLowerCase(), contains('négatives'));
    });

    test('23514 + "payment_method" → mode invalide', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation payment_method_check'),
      );
      expect(msg.toLowerCase(), contains('mode'));
    });

    test('23514 + "date_range" → date hors plage', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation leases_date_range_check'),
      );
      expect(msg.toLowerCase(), contains('plage'));
    });

    test('23514 + "notes" → notes trop longues', () {
      final msg = mapPostgrestError(
        _pge(code: '23514', message: 'check_violation notes_length'),
      );
      expect(msg.toLowerCase(), contains('notes'));
      expect(msg.toLowerCase(), contains('500'));
    });

    test('code 23503 → foreign key violation', () {
      final msg = mapPostgrestError(
        _pge(code: '23503', message: 'foreign_key_violation lease_id'),
      );
      expect(msg.toLowerCase(), contains('introuvable'));
    });
  });
}

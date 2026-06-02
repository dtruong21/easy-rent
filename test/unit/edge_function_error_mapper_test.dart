/// Tests de [mapEdgeFunctionError] et [ProfileIncompleteException].
///
/// Couvre :
/// - profile_incomplete exact → ProfileIncompleteException
/// - profile_incomplete avec suffixe long → ProfileIncompleteException (BUG-001)
/// - autre erreur 422 connue → message FR
/// - autre erreur 422 inconnue → message générique
/// - 401/403/404/500 → messages FR corrects
/// - erreur sans status connu → message générique non vide
library;

import 'package:easyrent/core/utils/edge_function_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

FunctionException _fe({required int status, Map<String, dynamic>? details}) =>
    FunctionException(status: status, details: details);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('422 profile_incomplete — BUG-001 (matching startsWith)', () {
    test(
      'error exact "profile_incomplete" → lève ProfileIncompleteException',
      () {
        expect(
          () => mapEdgeFunctionError(
            _fe(
              status: 422,
              details: {
                'error': 'profile_incomplete',
                'missing': ['full_name', 'address'],
              },
            ),
          ),
          throwsA(isA<ProfileIncompleteException>()),
        );
      },
    );

    test(
      'error avec suffixe "profile_incomplete — message long" → lève ProfileIncompleteException',
      () {
        expect(
          () => mapEdgeFunctionError(
            _fe(
              status: 422,
              details: {
                'error':
                    'profile_incomplete — completez votre profil bailleur avant de generer une quittance',
                'missing': ['full_name'],
              },
            ),
          ),
          throwsA(isA<ProfileIncompleteException>()),
        );
      },
    );

    test('ProfileIncompleteException contient les champs missing', () {
      try {
        mapEdgeFunctionError(
          _fe(
            status: 422,
            details: {
              'error': 'profile_incomplete',
              'missing': ['full_name', 'address'],
            },
          ),
        );
        fail('devrait lever ProfileIncompleteException');
      } on ProfileIncompleteException catch (e) {
        expect(e.missing, containsAll(['full_name', 'address']));
      }
    });

    test('missing absent → ProfileIncompleteException avec liste vide', () {
      try {
        mapEdgeFunctionError(
          _fe(status: 422, details: {'error': 'profile_incomplete'}),
        );
        fail('devrait lever ProfileIncompleteException');
      } on ProfileIncompleteException catch (e) {
        expect(e.missing, isEmpty);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('422 autres erreurs', () {
    test('no_payments_found → message paiement', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 422, details: {'error': 'no_payments_found'}),
      );
      expect(msg.toLowerCase(), contains('paiement'));
    });

    test('payments_different_leases → message baux différents', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 422, details: {'error': 'payments_different_leases'}),
      );
      expect(msg.toLowerCase(), contains('baux'));
    });

    test('inconsistent_dates → message dates', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 422, details: {'error': 'inconsistent_dates'}),
      );
      expect(msg.toLowerCase(), contains('date'));
    });

    test('code inconnu → message générique non vide', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 422, details: {'error': 'autre_chose_inconnue'}),
      );
      expect(msg, isNotEmpty);
    });

    test('details null → message générique non vide', () {
      final msg = mapEdgeFunctionError(_fe(status: 422));
      expect(msg, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('codes HTTP standard', () {
    test('401 → session expirée', () {
      final msg = mapEdgeFunctionError(_fe(status: 401));
      expect(msg.toLowerCase(), contains('session'));
    });

    test('403 → droits insuffisants', () {
      final msg = mapEdgeFunctionError(_fe(status: 403));
      expect(msg.toLowerCase(), contains('droits'));
    });

    test('404 → introuvable', () {
      final msg = mapEdgeFunctionError(_fe(status: 404));
      expect(msg.toLowerCase(), contains('introuvable'));
    });

    test('500 → erreur génération PDF', () {
      final msg = mapEdgeFunctionError(_fe(status: 500));
      expect(msg.toLowerCase(), contains('pdf'));
    });

    test('status inconnu → message générique non vide', () {
      final msg = mapEdgeFunctionError(_fe(status: 418));
      expect(msg, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('ProfileIncompleteException.toString', () {
    test('contient les champs manquants', () {
      final ex = const ProfileIncompleteException(
        missing: ['full_name', 'phone'],
      );
      expect(ex.toString(), contains('full_name'));
      expect(ex.toString(), contains('phone'));
    });
  });
}

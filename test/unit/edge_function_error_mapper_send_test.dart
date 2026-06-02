/// Tests des nouveaux codes FEAT-008 dans [mapEdgeFunctionError].
///
/// Couvre :
/// - 422 tenant_no_email → lève [TenantNoEmailException]
/// - 422 receipt_invalid → lève [ReceiptInvalidForSendException]
/// - 422 pdf_unavailable → lève [PdfUnavailableException]
/// - 429 quota_exceeded → lève [EmailQuotaExceededException]
/// - 429 code inconnu → retourne message générique
/// - toString des nouvelles exceptions
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
  group('422 tenant_no_email', () {
    test('lève TenantNoEmailException', () {
      expect(
        () => mapEdgeFunctionError(
          _fe(status: 422, details: {'error': 'tenant_no_email'}),
        ),
        throwsA(isA<TenantNoEmailException>()),
      );
    });

    test('TenantNoEmailException.toString est non vide', () {
      const ex = TenantNoEmailException();
      expect(ex.toString(), isNotEmpty);
      expect(ex.toString(), contains('email'));
    });
  });

  // -------------------------------------------------------------------------
  group('422 receipt_invalid', () {
    test('lève ReceiptInvalidForSendException', () {
      expect(
        () => mapEdgeFunctionError(
          _fe(status: 422, details: {'error': 'receipt_invalid'}),
        ),
        throwsA(isA<ReceiptInvalidForSendException>()),
      );
    });

    test('ReceiptInvalidForSendException.toString est non vide', () {
      const ex = ReceiptInvalidForSendException();
      expect(ex.toString(), isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('422 pdf_unavailable', () {
    test('lève PdfUnavailableException', () {
      expect(
        () => mapEdgeFunctionError(
          _fe(status: 422, details: {'error': 'pdf_unavailable'}),
        ),
        throwsA(isA<PdfUnavailableException>()),
      );
    });

    test('PdfUnavailableException.toString est non vide', () {
      const ex = PdfUnavailableException();
      expect(ex.toString(), isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('429 quota_exceeded', () {
    test('lève EmailQuotaExceededException', () {
      expect(
        () => mapEdgeFunctionError(
          _fe(status: 429, details: {'error': 'quota_exceeded'}),
        ),
        throwsA(isA<EmailQuotaExceededException>()),
      );
    });

    test('EmailQuotaExceededException.toString est non vide', () {
      const ex = EmailQuotaExceededException();
      expect(ex.toString(), isNotEmpty);
      expect(ex.toString(), contains('quota'));
    });

    test('429 code inconnu → message générique non vide', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 429, details: {'error': 'rate_limit_other'}),
      );
      expect(msg, isNotEmpty);
    });

    test('429 sans details → message générique non vide', () {
      final msg = mapEdgeFunctionError(_fe(status: 429));
      expect(msg, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('codes existants non affectés par FEAT-008', () {
    test('422 no_payments_found → message paiement (inchangé)', () {
      final msg = mapEdgeFunctionError(
        _fe(status: 422, details: {'error': 'no_payments_found'}),
      );
      expect(msg.toLowerCase(), contains('paiement'));
    });

    test('500 → message erreur (inchangé)', () {
      final msg = mapEdgeFunctionError(_fe(status: 500));
      expect(msg, isNotEmpty);
    });
  });
}

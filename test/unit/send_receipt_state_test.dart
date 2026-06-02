/// Tests du modèle [SendReceiptState] — freezed equality et pattern matching.
library;

import 'package:easyrent/features/receipts/domain/send_receipt_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SendReceiptState freezed equality', () {
    test('deux idle sont égaux', () {
      expect(
        const SendReceiptState.idle(),
        equals(const SendReceiptState.idle()),
      );
    });

    test('deux submitting sont égaux', () {
      expect(
        const SendReceiptState.submitting(),
        equals(const SendReceiptState.submitting()),
      );
    });

    test('deux tenantNoEmail sont égaux', () {
      expect(
        const SendReceiptState.tenantNoEmail(),
        equals(const SendReceiptState.tenantNoEmail()),
      );
    });

    test('deux rateLimited sont égaux', () {
      expect(
        const SendReceiptState.rateLimited(),
        equals(const SendReceiptState.rateLimited()),
      );
    });

    test('deux error avec même message sont égaux', () {
      expect(
        const SendReceiptState.error(message: 'oops'),
        equals(const SendReceiptState.error(message: 'oops')),
      );
    });

    test('deux error avec messages différents ne sont pas égaux', () {
      expect(
        const SendReceiptState.error(message: 'a'),
        isNot(equals(const SendReceiptState.error(message: 'b'))),
      );
    });

    test('deux success avec même date et email sont égaux', () {
      final date = DateTime(2026, 6, 1);
      final s1 = SendReceiptState.success(sentAt: date, sentToEmail: 'a@b.com');
      final s2 = SendReceiptState.success(sentAt: date, sentToEmail: 'a@b.com');
      expect(s1, equals(s2));
    });

    test('deux confirmingResend avec mêmes valeurs sont égaux', () {
      final date = DateTime(2026, 5, 1);
      final s1 = SendReceiptState.confirmingResend(
        previousSentAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      final s2 = SendReceiptState.confirmingResend(
        previousSentAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      expect(s1, equals(s2));
    });
  });

  group('SendReceiptState pattern matching (switch)', () {
    SendReceiptState state;

    test('idle → pattern match', () {
      state = const SendReceiptState.idle();
      final label = switch (state) {
        SendReceiptIdle() => 'idle',
        SendReceiptSubmitting() => 'submitting',
        SendReceiptConfirmingResend() => 'confirming',
        SendReceiptSuccess() => 'success',
        SendReceiptError() => 'error',
        SendReceiptTenantNoEmail() => 'noEmail',
        SendReceiptRateLimited() => 'rate',
      };
      expect(label, 'idle');
    });

    test('success → accès aux champs', () {
      final date = DateTime(2026, 6, 1);
      state = SendReceiptState.success(sentAt: date, sentToEmail: 'x@y.com');
      if (state case SendReceiptSuccess(:final sentAt, :final sentToEmail)) {
        expect(sentAt, date);
        expect(sentToEmail, 'x@y.com');
      } else {
        fail('attendait SendReceiptSuccess');
      }
    });

    test('confirmingResend → accès aux champs', () {
      final date = DateTime(2026, 5, 15);
      state = SendReceiptState.confirmingResend(
        previousSentAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      if (state case SendReceiptConfirmingResend(
        :final previousSentAt,
        :final previousMaskedEmail,
      )) {
        expect(previousSentAt, date);
        expect(previousMaskedEmail, 'j***@ex.com');
      } else {
        fail('attendait SendReceiptConfirmingResend');
      }
    });

    test('error → accès au message', () {
      state = const SendReceiptState.error(message: 'erreur de test');
      if (state case SendReceiptError(:final message)) {
        expect(message, 'erreur de test');
      } else {
        fail('attendait SendReceiptError');
      }
    });
  });
}

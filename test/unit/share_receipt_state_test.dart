/// Tests du modèle [ShareReceiptState] — freezed equality et pattern matching.
library;

import 'package:easyrent/features/receipts/domain/share_receipt_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareReceiptState freezed equality', () {
    test('deux idle sont égaux', () {
      expect(
        const ShareReceiptState.idle(),
        equals(const ShareReceiptState.idle()),
      );
    });

    test('deux preparing sont égaux', () {
      expect(
        const ShareReceiptState.preparing(),
        equals(const ShareReceiptState.preparing()),
      );
    });

    test('deux tenantNoEmail sont égaux', () {
      expect(
        const ShareReceiptState.tenantNoEmail(),
        equals(const ShareReceiptState.tenantNoEmail()),
      );
    });

    test('deux error avec même message sont égaux', () {
      expect(
        const ShareReceiptState.error(message: 'oops'),
        equals(const ShareReceiptState.error(message: 'oops')),
      );
    });

    test('deux error avec messages différents ne sont pas égaux', () {
      expect(
        const ShareReceiptState.error(message: 'a'),
        isNot(equals(const ShareReceiptState.error(message: 'b'))),
      );
    });

    test('deux shared avec mêmes valeurs sont égaux', () {
      final date = DateTime(2026, 6, 1);
      final s1 = ShareReceiptState.shared(
        sharedAt: date,
        sharedToEmail: 'a@b.com',
        usedNativeShare: true,
      );
      final s2 = ShareReceiptState.shared(
        sharedAt: date,
        sharedToEmail: 'a@b.com',
        usedNativeShare: true,
      );
      expect(s1, equals(s2));
    });

    test('deux confirmingResend avec mêmes valeurs sont égaux', () {
      final date = DateTime(2026, 5, 1);
      final s1 = ShareReceiptState.confirmingResend(
        previousSharedAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      final s2 = ShareReceiptState.confirmingResend(
        previousSharedAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      expect(s1, equals(s2));
    });
  });

  group('ShareReceiptState pattern matching (switch)', () {
    ShareReceiptState state;

    test('idle → pattern match', () {
      state = const ShareReceiptState.idle();
      final label = switch (state) {
        ShareReceiptIdle() => 'idle',
        ShareReceiptPreparing() => 'preparing',
        ShareReceiptConfirmingResend() => 'confirming',
        ShareReceiptShared() => 'shared',
        ShareReceiptError() => 'error',
        ShareReceiptTenantNoEmail() => 'noEmail',
      };
      expect(label, 'idle');
    });

    test('shared → accès aux champs', () {
      final date = DateTime(2026, 6, 1);
      state = ShareReceiptState.shared(
        sharedAt: date,
        sharedToEmail: 'x@y.com',
        usedNativeShare: false,
      );
      if (state case ShareReceiptShared(
        :final sharedAt,
        :final sharedToEmail,
        :final usedNativeShare,
      )) {
        expect(sharedAt, date);
        expect(sharedToEmail, 'x@y.com');
        expect(usedNativeShare, false);
      } else {
        fail('attendait ShareReceiptShared');
      }
    });

    test('confirmingResend → accès aux champs', () {
      final date = DateTime(2026, 5, 15);
      state = ShareReceiptState.confirmingResend(
        previousSharedAt: date,
        previousMaskedEmail: 'j***@ex.com',
      );
      if (state case ShareReceiptConfirmingResend(
        :final previousSharedAt,
        :final previousMaskedEmail,
      )) {
        expect(previousSharedAt, date);
        expect(previousMaskedEmail, 'j***@ex.com');
      } else {
        fail('attendait ShareReceiptConfirmingResend');
      }
    });

    test('error → accès au message', () {
      state = const ShareReceiptState.error(message: 'erreur de test');
      if (state case ShareReceiptError(:final message)) {
        expect(message, 'erreur de test');
      } else {
        fail('attendait ShareReceiptError');
      }
    });
  });
}

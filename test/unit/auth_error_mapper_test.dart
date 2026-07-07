import 'package:easyrent/features/auth/data/auth_error_mapper.dart';
import 'package:easyrent/features/auth/domain/auth_error.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthErrorMapper.fromException (Firebase codes)', () {
    FirebaseAuthException e(String code, [String message = '']) =>
        FirebaseAuthException(code: code, message: message);

    test('invalid-credential → invalidCredentials', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-credential')),
        AuthError.invalidCredentials,
      );
    });

    test('wrong-password → invalidCredentials', () {
      expect(
        AuthErrorMapper.fromException(e('wrong-password')),
        AuthError.invalidCredentials,
      );
    });

    test('user-not-found → invalidCredentials (anti-énumération)', () {
      expect(
        AuthErrorMapper.fromException(e('user-not-found')),
        AuthError.invalidCredentials,
      );
    });

    test('invalid-email → invalidCredentials', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-email')),
        AuthError.invalidCredentials,
      );
    });

    test('user-disabled → userDisabled', () {
      expect(
        AuthErrorMapper.fromException(e('user-disabled')),
        AuthError.userDisabled,
      );
    });

    test('email-already-in-use → emailAlreadyInUse', () {
      expect(
        AuthErrorMapper.fromException(e('email-already-in-use')),
        AuthError.emailAlreadyInUse,
      );
    });

    test('weak-password → weakPassword', () {
      expect(
        AuthErrorMapper.fromException(e('weak-password')),
        AuthError.weakPassword,
      );
    });

    test('too-many-requests → tooManyRequests', () {
      expect(
        AuthErrorMapper.fromException(e('too-many-requests')),
        AuthError.tooManyRequests,
      );
    });

    test('requires-recent-login → requiresRecentLogin (FEAT-025)', () {
      expect(
        AuthErrorMapper.fromException(e('requires-recent-login')),
        AuthError.requiresRecentLogin,
      );
    });

    test('expired-action-code → expiredActionCode', () {
      expect(
        AuthErrorMapper.fromException(e('expired-action-code')),
        AuthError.expiredActionCode,
      );
    });

    test('invalid-action-code → expiredActionCode', () {
      expect(
        AuthErrorMapper.fromException(e('invalid-action-code')),
        AuthError.expiredActionCode,
      );
    });

    test('network-request-failed → networkRequestFailed', () {
      expect(
        AuthErrorMapper.fromException(e('network-request-failed')),
        AuthError.networkRequestFailed,
      );
    });

    test('operation-not-allowed → operationNotAllowed', () {
      expect(
        AuthErrorMapper.fromException(e('operation-not-allowed')),
        AuthError.operationNotAllowed,
      );
    });

    test('code inconnu → unknown', () {
      expect(
        AuthErrorMapper.fromException(e('unknown_code_xyz')),
        AuthError.unknown,
      );
    });
  });

  group('AuthErrorMapper.fromException (Google sign-in codes)', () {
    FirebaseAuthException e(String code, [String message = '']) =>
        FirebaseAuthException(code: code, message: message);

    test('popup-closed-by-user → googlePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('popup-closed-by-user')),
        AuthError.googlePopupClosed,
      );
    });

    test('popup-blocked → googlePopupBlocked', () {
      expect(
        AuthErrorMapper.fromException(e('popup-blocked')),
        AuthError.googlePopupBlocked,
      );
    });

    test(
      'account-exists-with-different-credential → accountExistsWithDifferentCredential',
      () {
        expect(
          AuthErrorMapper.fromException(
            e('account-exists-with-different-credential'),
          ),
          AuthError.accountExistsWithDifferentCredential,
        );
      },
    );

    test('cancelled-popup-request → googlePopupCancelledRequest', () {
      expect(
        AuthErrorMapper.fromException(e('cancelled-popup-request')),
        AuthError.googlePopupCancelledRequest,
      );
    });

    test('web-storage-unsupported → webStorageUnsupported', () {
      expect(
        AuthErrorMapper.fromException(e('web-storage-unsupported')),
        AuthError.webStorageUnsupported,
      );
    });

    test('baillan/google-new-user-on-login → googleNewUserOnLogin', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/google-new-user-on-login')),
        AuthError.googleNewUserOnLogin,
      );
    });

    test('baillan/rgpd-consent-declined → consentRequired', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/rgpd-consent-declined')),
        AuthError.consentRequired,
      );
    });

    test('baillan/popup-blocked → googlePopupBlocked', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/popup-blocked')),
        AuthError.googlePopupBlocked,
      );
    });

    test('baillan/popup-closed → googlePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/popup-closed')),
        AuthError.googlePopupClosed,
      );
    });
  });

  group('AuthErrorMapper.fromException (Apple sign-in codes)', () {
    FirebaseAuthException e(String code, [String message = '']) =>
        FirebaseAuthException(code: code, message: message);

    test('user-cancelled → applePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('user-cancelled')),
        AuthError.applePopupClosed,
      );
    });

    test('baillan/apple-new-user-on-login → appleNewUserOnLogin', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/apple-new-user-on-login')),
        AuthError.appleNewUserOnLogin,
      );
    });

    test('baillan/apple-rgpd-consent-declined → consentRequired', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/apple-rgpd-consent-declined')),
        AuthError.consentRequired,
      );
    });

    test('baillan/apple-popup-blocked → applePopupBlocked', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/apple-popup-blocked')),
        AuthError.applePopupBlocked,
      );
    });

    test('baillan/apple-popup-closed → applePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('baillan/apple-popup-closed')),
        AuthError.applePopupClosed,
      );
    });
  });

  group('AuthErrorMapper.fromException (OAuth natif mobile, FEAT-024)', () {
    FirebaseAuthException e(String code) => FirebaseAuthException(code: code);

    test('web-context-canceled (Android) → googlePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('web-context-canceled')),
        AuthError.googlePopupClosed,
      );
    });

    test('web-context-cancelled (iOS) → googlePopupClosed', () {
      expect(
        AuthErrorMapper.fromException(e('web-context-cancelled')),
        AuthError.googlePopupClosed,
      );
    });
  });
}

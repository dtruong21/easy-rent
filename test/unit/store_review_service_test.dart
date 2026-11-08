import 'package:easyrent/features/app_review/data/store_review_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web / hors app store → jamais', () {
    expect(
      canRateInStore(
        storeApp: false,
        platform: TargetPlatform.android,
        appStoreId: '',
      ),
      isFalse,
    );
  });
  test('Android app store → oui, même sans identifiant App Store', () {
    expect(
      canRateInStore(
        storeApp: true,
        platform: TargetPlatform.android,
        appStoreId: '',
      ),
      isTrue,
    );
  });
  test('iOS sans APP_STORE_ID → non', () {
    expect(
      canRateInStore(
        storeApp: true,
        platform: TargetPlatform.iOS,
        appStoreId: '',
      ),
      isFalse,
    );
  });
  test('iOS avec identifiant → oui', () {
    expect(
      canRateInStore(
        storeApp: true,
        platform: TargetPlatform.iOS,
        appStoreId: '1234567890',
      ),
      isTrue,
    );
  });
}

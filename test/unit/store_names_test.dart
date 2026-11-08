import 'package:easyrent/features/paid_plan/domain/store_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nom du store selon la plateforme', () {
    expect(storeNameForPlatform(TargetPlatform.iOS), 'App Store');
    expect(storeNameForPlatform(TargetPlatform.android), 'Google Play');
  });

  test('nom du store d\'origine de l\'abonnement', () {
    expect(storeNameForProStore('app_store'), 'App Store');
    expect(storeNameForProStore('play_store'), 'Google Play');
  });

  test('URL de gestion de repli, par store d\'origine', () {
    expect(
      storeManagementFallbackUri('app_store').toString(),
      'https://apps.apple.com/account/subscriptions',
    );
    expect(
      storeManagementFallbackUri('play_store').toString(),
      'https://play.google.com/store/account/subscriptions',
    );
  });
}

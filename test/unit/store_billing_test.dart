/// Tests unitaires du prédicat [isStoreApp] (conformité stores : aucun achat
/// hors achat intégré dans les apps iOS/Android).
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool? originalOverride;
  late TargetPlatform? originalPlatform;

  setUp(() {
    originalOverride = debugIsStoreAppOverride;
    originalPlatform = debugDefaultTargetPlatformOverride;
  });

  tearDown(() {
    debugIsStoreAppOverride = originalOverride;
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  test('override true → app store', () {
    debugIsStoreAppOverride = true;
    expect(isStoreApp, isTrue);
  });

  test('override false → web (parcours Stripe)', () {
    debugIsStoreAppOverride = false;
    expect(isStoreApp, isFalse);
  });

  test('sans override, plateforme iOS → app store', () {
    debugIsStoreAppOverride = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isStoreApp, isTrue);
  });

  test('sans override, plateforme Android → app store', () {
    debugIsStoreAppOverride = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isStoreApp, isTrue);
  });

  test('sans override, plateforme macOS → pas une app store', () {
    debugIsStoreAppOverride = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isStoreApp, isFalse);
  });
}

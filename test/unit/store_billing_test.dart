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

  group('achat intégré (FEAT-044e)', () {
    late bool? originalIap;
    setUp(() => originalIap = debugInAppPurchaseEnabledOverride);
    tearDown(() => debugInAppPurchaseEnabledOverride = originalIap);

    test('sans IAP_ENABLED → achat intégré coupé, même en app store', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = null;
      expect(isInAppPurchaseEnabled, isFalse);
    });

    test('canOfferUpgrade : web → vrai (parcours Stripe)', () {
      debugIsStoreAppOverride = false;
      debugInAppPurchaseEnabledOverride = null;
      expect(canOfferUpgrade, isTrue);
    });

    test('canOfferUpgrade : app store sans achat intégré → faux', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = false;
      expect(canOfferUpgrade, isFalse);
    });

    test('canOfferUpgrade : app store avec achat intégré → vrai', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = true;
      expect(canOfferUpgrade, isTrue);
    });
  });

  group('revenueCatApiKeyFor', () {
    test('iOS → clé Apple', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.iOS,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        'appl_x',
      );
    });

    test('Android → clé Google', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.android,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        'goog_y',
      );
    });

    test('clé vide ou blanche → null', () {
      expect(
        revenueCatApiKeyFor(TargetPlatform.iOS, appleKey: '  ', googleKey: ''),
        isNull,
      );
    });

    test('plateforme sans achat intégré → null', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.macOS,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        isNull,
      );
    });

    test('sans dart-define → null', () {
      expect(revenueCatApiKeyFor(TargetPlatform.iOS), isNull);
      expect(revenueCatApiKeyFor(TargetPlatform.android), isNull);
    });
  });
}

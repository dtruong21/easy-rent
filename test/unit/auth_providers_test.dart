/// Fournisseurs de connexion proposés en v1 (décision du 2026-10-03).
library;

import 'package:easyrent/core/config/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugGoogleSignInOfferedOverride = null;
    debugAppleSignInOfferedOverride = null;
  });

  test('Android : Google proposé', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isGoogleSignInOffered, isTrue);
  });

  test('iOS : Google masqué (règle App Store 4.8 tant qu\'Apple manque)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isGoogleSignInOffered, isFalse);
  });

  test('Apple masqué partout en v1', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isAppleSignInOffered, isFalse, reason: '$platform');
    }
  });

  test('les forçages de test priment', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    debugGoogleSignInOfferedOverride = true;
    debugAppleSignInOfferedOverride = true;
    expect(isGoogleSignInOffered, isTrue);
    expect(isAppleSignInOffered, isTrue);
  });
}

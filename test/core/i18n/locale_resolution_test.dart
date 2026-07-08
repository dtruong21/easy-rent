/// Tests de [resolveLocale] — logique de `localeResolutionCallback`
/// (FEAT-043), extraite en fonction pure pour être testée sans monter de
/// [MaterialApp].
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const supported = [Locale('fr'), Locale('en')];

  group('resolveLocale', () {
    test('device null → fallback fr', () {
      expect(resolveLocale(null, supported), const Locale('fr'));
    });

    test('device en-US → en (supporté)', () {
      expect(
        resolveLocale(const Locale('en', 'US'), supported),
        const Locale('en'),
      );
    });

    test('device en-GB → en (supporté, languageCode seul comparé)', () {
      expect(
        resolveLocale(const Locale('en', 'GB'), supported),
        const Locale('en'),
      );
    });

    test('device fr-FR → fr (supporté)', () {
      expect(
        resolveLocale(const Locale('fr', 'FR'), supported),
        const Locale('fr'),
      );
    });

    test('device de-DE (non supporté) → fallback fr', () {
      expect(
        resolveLocale(const Locale('de', 'DE'), supported),
        const Locale('fr'),
      );
    });

    test('device es (non supporté) → fallback fr', () {
      expect(resolveLocale(const Locale('es'), supported), const Locale('fr'));
    });
  });
}

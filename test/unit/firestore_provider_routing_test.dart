/// Table de vérité du choix de base Firestore (ADR 0003 + build Test Lab).
library;

import 'package:easyrent/core/config/firestore_provider.dart';
import 'package:flutter_test/flutter_test.dart';

bool _staging({
  bool isWeb = false,
  bool isDev = true,
  bool useEmulator = false,
  bool useMobileStaging = false,
}) => shouldUseStagingDatabase(
  isWeb: isWeb,
  isDev: isDev,
  useEmulator: useEmulator,
  useMobileStaging: useMobileStaging,
);

void main() {
  test('web staging (APP_ENV=dev) → staging', () {
    expect(_staging(isWeb: true), isTrue);
  });
  test('web prod → prod', () {
    expect(_staging(isWeb: true, isDev: false), isFalse);
  });
  test('mobile sans MOBILE_STAGING → prod (même APP_ENV=dev)', () {
    expect(_staging(), isFalse);
  });
  test('mobile avec MOBILE_STAGING → staging', () {
    expect(_staging(useMobileStaging: true), isTrue);
  });
  test('émulateur prioritaire (web)', () {
    expect(_staging(isWeb: true, useEmulator: true), isFalse);
  });
  test('émulateur prioritaire (mobile staging)', () {
    expect(_staging(useMobileStaging: true, useEmulator: true), isFalse);
  });
}

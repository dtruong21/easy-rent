import 'package:easyrent/features/dashboard/application/onboarding_dismissed_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('défaut false ; dismiss() → true et persiste', () async {
    final storage = OnboardingDismissedStorage();
    expect(await storage.read(), isFalse);
    await storage.write(true);
    expect(await storage.read(), isTrue);
  });
}

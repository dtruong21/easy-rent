import 'package:easyrent/features/app_review/data/review_solicitation_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('jamais sollicité → null', () async {
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), isNull);
  });

  test('markSolicited puis lecture → même instant', () async {
    final at = DateTime.utc(2026, 10, 9, 8, 30);
    await ReviewSolicitationStorage().markSolicited(at);
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), at);
  });

  test('valeur illisible → null (jamais d\'exception)', () async {
    SharedPreferences.setMockInitialValues({'review_solicited_at': 'n/a'});
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), isNull);
  });
}

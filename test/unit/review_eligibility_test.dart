import 'package:easyrent/features/app_review/domain/review_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 9, 12);
  bool eligible({
    bool full = true,
    Duration age = const Duration(days: 30),
    bool hasProperty = true,
    Duration? sinceLast,
  }) => isReviewSolicitationEligible(
    fullyAuthenticated: full,
    accountCreatedAt: now.subtract(age),
    hasProperty: hasProperty,
    lastSolicitedAt: sinceLast == null ? null : now.subtract(sinceLast),
    now: now,
  );

  test('cas nominal → éligible', () => expect(eligible(), isTrue));
  test(
    'compte non complet → non',
    () => expect(eligible(full: false), isFalse),
  );
  test('compte de 14 jours → non', () {
    expect(eligible(age: const Duration(days: 14)), isFalse);
  });
  test('compte de 15 jours pile → oui (borne incluse)', () {
    expect(eligible(age: kReviewMinAccountAge), isTrue);
  });
  test('aucun bien → non', () => expect(eligible(hasProperty: false), isFalse));
  test('sollicité il y a 119 jours → non', () {
    expect(eligible(sinceLast: const Duration(days: 119)), isFalse);
  });
  test('sollicité il y a 120 jours pile → oui (borne incluse)', () {
    expect(eligible(sinceLast: kReviewSolicitationInterval), isTrue);
  });
  test(
    'jamais sollicité → oui',
    () => expect(eligible(sinceLast: null), isTrue),
  );
}

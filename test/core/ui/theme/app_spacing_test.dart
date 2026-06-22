/// Tests unitaires pour [AppSpacing] (ThemeExtension).
library;

import 'package:easyrent/core/ui/theme/app_spacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSpacing defaults', () {
    test('valeurs par défaut correctes', () {
      const spacing = AppSpacing();
      expect(spacing.xs, 4);
      expect(spacing.sm, 8);
      expect(spacing.md, 12);
      expect(spacing.lg, 16);
      expect(spacing.xl, 24);
      expect(spacing.xxl, 32);
      expect(spacing.gridGap, 16);
      expect(spacing.cardPaddingCompact, 12);
      expect(spacing.cardPaddingStandard, 16);
    });
  });

  group('AppSpacing.copyWith', () {
    test('copyWith null → valeurs inchangées', () {
      const original = AppSpacing();
      final copy = original.copyWith();
      expect(copy.xs, original.xs);
      expect(copy.gridGap, original.gridGap);
    });

    test('copyWith avec xs=2 → xs changé, autres inchangés', () {
      const original = AppSpacing();
      final copy = original.copyWith(xs: 2);
      expect(copy.xs, 2.0);
      expect(copy.sm, original.sm);
    });
  });

  group('AppSpacing.lerp', () {
    test('lerp t=0 → retourne this', () {
      const a = AppSpacing();
      const b = AppSpacing(xs: 8, sm: 16, md: 24);
      final result = a.lerp(b, 0.0);
      expect(result.xs, a.xs);
    });

    test('lerp t=1 → retourne other', () {
      const a = AppSpacing();
      const b = AppSpacing(xs: 8, sm: 16, md: 24);
      final result = a.lerp(b, 1.0);
      expect(result.xs, b.xs);
    });

    test('lerp null → retourne this', () {
      const a = AppSpacing();
      final result = a.lerp(null, 0.5);
      expect(result.xs, a.xs);
    });
  });
}

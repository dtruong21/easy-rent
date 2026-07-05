/// Tests unitaires pour [AppColors] (ThemeExtension).
library;

import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors.statusFor', () {
    test('success → colorSet success', () {
      final colors = AppColors.light;
      expect(colors.statusFor(StatusPillTone.success), same(colors.success));
    });

    test('warning → colorSet warning', () {
      final colors = AppColors.light;
      expect(colors.statusFor(StatusPillTone.warning), same(colors.warning));
    });

    test('danger → colorSet danger', () {
      final colors = AppColors.light;
      expect(colors.statusFor(StatusPillTone.danger), same(colors.danger));
    });

    test('info → colorSet info', () {
      final colors = AppColors.light;
      expect(colors.statusFor(StatusPillTone.info), same(colors.info));
    });

    test('neutral → colorSet neutral', () {
      final colors = AppColors.light;
      expect(colors.statusFor(StatusPillTone.neutral), same(colors.neutral));
    });
  });

  group('AppColors.copyWith', () {
    test('copyWith null → retourne même valeurs', () {
      const original = AppColors.light;
      final copy = original.copyWith();
      expect(copy.success.surface, original.success.surface);
      expect(copy.warning.solid, original.warning.solid);
      expect(copy.danger.onSurface, original.danger.onSurface);
    });

    test(
      'copyWith avec success remplacé → success changé, autres inchangés',
      () {
        const original = AppColors.light;
        const newSuccess = StatusColorSet(
          surface: Color(0xFF000001),
          onSurface: Color(0xFF000002),
          solid: Color(0xFF000003),
          onSolid: Color(0xFF000004),
        );
        final copy = original.copyWith(success: newSuccess);
        expect(copy.success.surface, const Color(0xFF000001));
        expect(copy.warning.surface, original.warning.surface);
        expect(copy.neutral.solid, original.neutral.solid);
      },
    );
  });

  group('AppColors.lerp', () {
    test('lerp t=0 → retourne this', () {
      const a = AppColors.light;
      const b = AppColors.dark;
      final result = a.lerp(b, 0.0);
      expect(result.success.surface, a.success.surface);
    });

    test('lerp t=1 → retourne other', () {
      const a = AppColors.light;
      const b = AppColors.dark;
      final result = a.lerp(b, 1.0);
      expect(result.success.surface, b.success.surface);
    });

    test('lerp null → retourne this', () {
      const a = AppColors.light;
      final result = a.lerp(null, 0.5);
      expect(result.success.surface, a.success.surface);
    });

    test('lerp t=0.5 → valeur intermédiaire', () {
      const a = AppColors.light;
      const b = AppColors.dark;
      final result = a.lerp(b, 0.5);
      // La couleur intermédiaire ne doit être ni a ni b.
      expect(result.success.surface, isNot(a.success.surface));
      expect(result.success.surface, isNot(b.success.surface));
    });
  });

  group('AppColors dark preset', () {
    test('success dark surface est sombre', () {
      const colors = AppColors.dark;
      final surface = colors.success.surface;
      // Composante rouge faible = couleur sombre.
      expect(surface.r, lessThan(0.2));
    });

    test('danger dark solid est rouge', () {
      const colors = AppColors.dark;
      final solid = colors.danger.solid;
      // Composante rouge élevée.
      expect(solid.r, greaterThan(0.8));
    });
  });

  group('StatusColorSet.lerp', () {
    test('lerp t=0 → surface inchangée', () {
      const a = StatusColorSet(
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF000000),
        solid: Color(0xFF0000FF),
        onSolid: Color(0xFFFFFFFF),
      );
      const b = StatusColorSet(
        surface: Color(0xFF000000),
        onSurface: Color(0xFFFFFFFF),
        solid: Color(0xFFFF0000),
        onSolid: Color(0xFF000000),
      );
      final result = a.lerp(b, 0.0);
      expect(result.surface, a.surface);
    });
  });
}

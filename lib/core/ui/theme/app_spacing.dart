import 'dart:ui';

import 'package:flutter/material.dart';

/// Extension de thème Material 3 pour l'espacement EasyRent.
///
/// Accès : `Theme.of(context).extension<AppSpacing>()!`.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.xxl = 32,
    this.gridGap = 16,
    this.cardPaddingCompact = 12,
    this.cardPaddingStandard = 16,
  });

  /// Extra-small : 4px
  final double xs;

  /// Small : 8px
  final double sm;

  /// Medium : 12px
  final double md;

  /// Large : 16px
  final double lg;

  /// Extra-large : 24px
  final double xl;

  /// Extra-extra-large : 32px
  final double xxl;

  /// Espacement entre les cellules de grille : 16px
  final double gridGap;

  /// Padding interne d'une carte compacte : 12px
  final double cardPaddingCompact;

  /// Padding interne d'une carte standard : 16px
  final double cardPaddingStandard;

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? gridGap,
    double? cardPaddingCompact,
    double? cardPaddingStandard,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      gridGap: gridGap ?? this.gridGap,
      cardPaddingCompact: cardPaddingCompact ?? this.cardPaddingCompact,
      cardPaddingStandard: cardPaddingStandard ?? this.cardPaddingStandard,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      xxl: lerpDouble(xxl, other.xxl, t)!,
      gridGap: lerpDouble(gridGap, other.gridGap, t)!,
      cardPaddingCompact: lerpDouble(
        cardPaddingCompact,
        other.cardPaddingCompact,
        t,
      )!,
      cardPaddingStandard: lerpDouble(
        cardPaddingStandard,
        other.cardPaddingStandard,
        t,
      )!,
    );
  }
}

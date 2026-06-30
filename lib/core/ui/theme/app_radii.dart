import 'dart:ui';

import 'package:flutter/material.dart';

/// Extension de thème Material 3 pour les rayons de bordure Baillan.
///
/// Accès : `Theme.of(context).extension<AppRadii>()!`.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({this.sm = 6, this.md = 10, this.lg = 14, this.pill = 999});

  /// Petit rayon : 6px
  final double sm;

  /// Rayon moyen (carte par défaut) : 10px
  final double md;

  /// Grand rayon : 14px
  final double lg;

  /// Rayon pilule : 999px (cercle complet)
  final double pill;

  @override
  AppRadii copyWith({double? sm, double? md, double? lg, double? pill}) {
    return AppRadii(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}

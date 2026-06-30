import 'package:flutter/material.dart';

import '../cards/status_pill_tone.dart';

/// Ensemble de couleurs pour un tone de statut donné.
///
/// - [surface] : fond pâle (subtle background)
/// - [onSurface] : texte/icône sur [surface] (contraste WCAG AA garanti)
/// - [solid] : fond saturé (filled background)
/// - [onSolid] : texte/icône sur [solid]
@immutable
class StatusColorSet {
  const StatusColorSet({
    required this.surface,
    required this.onSurface,
    required this.solid,
    required this.onSolid,
  });

  final Color surface;
  final Color onSurface;
  final Color solid;
  final Color onSolid;

  StatusColorSet lerp(StatusColorSet other, double t) {
    return StatusColorSet(
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      solid: Color.lerp(solid, other.solid, t)!,
      onSolid: Color.lerp(onSolid, other.onSolid, t)!,
    );
  }
}

/// Extension de thème Material 3 pour la palette de statuts Baillan.
///
/// 5 tones × 4 couleurs, déclinés light / dark.
/// Accès : `Theme.of(context).extension<AppColors>()!.statusFor(tone)`.
///
/// Contrastes WCAG AA garantis pour chaque paire surface/onSurface.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
  });

  final StatusColorSet success;
  final StatusColorSet warning;
  final StatusColorSet danger;
  final StatusColorSet info;
  final StatusColorSet neutral;

  // ---------------------------------------------------------------------------
  // Presets light / dark
  // ---------------------------------------------------------------------------

  /// Palette claire (validée WCAG AA).
  static const AppColors light = AppColors(
    success: StatusColorSet(
      surface: Color(0xFFE6F5EC),
      onSurface: Color(0xFF0F5132),
      solid: Color(0xFF15803D),
      onSolid: Color(0xFFFFFFFF),
    ),
    warning: StatusColorSet(
      surface: Color(0xFFFEF5E1),
      onSurface: Color(0xFF8A4B00),
      solid: Color(0xFFB45309),
      onSolid: Color(0xFFFFFFFF),
    ),
    danger: StatusColorSet(
      surface: Color(0xFFFCE6E6),
      onSurface: Color(0xFF991B1B),
      solid: Color(0xFFDC2626),
      onSolid: Color(0xFFFFFFFF),
    ),
    info: StatusColorSet(
      surface: Color(0xFFE0F2F9),
      onSurface: Color(0xFF0C4A6E),
      solid: Color(0xFF0284C7),
      onSolid: Color(0xFFFFFFFF),
    ),
    neutral: StatusColorSet(
      surface: Color(0xFFF1F5F9),
      onSurface: Color(0xFF334155),
      solid: Color(0xFF64748B),
      onSolid: Color(0xFFFFFFFF),
    ),
  );

  /// Palette sombre (validée WCAG AA).
  static const AppColors dark = AppColors(
    success: StatusColorSet(
      surface: Color(0xFF14352B),
      onSurface: Color(0xFF86EFAC),
      solid: Color(0xFF22C55E),
      onSolid: Color(0xFF052E16),
    ),
    warning: StatusColorSet(
      surface: Color(0xFF3F2A0C),
      onSurface: Color(0xFFFCD34D),
      solid: Color(0xFFEAB308),
      onSolid: Color(0xFF422006),
    ),
    danger: StatusColorSet(
      surface: Color(0xFF3F1212),
      onSurface: Color(0xFFFCA5A5),
      solid: Color(0xFFEF4444),
      onSolid: Color(0xFF450A0A),
    ),
    info: StatusColorSet(
      surface: Color(0xFF0C2A3F),
      onSurface: Color(0xFF7DD3FC),
      solid: Color(0xFF38BDF8),
      onSolid: Color(0xFF082F49),
    ),
    neutral: StatusColorSet(
      surface: Color(0xFF1E293B),
      onSurface: Color(0xFFCBD5E1),
      solid: Color(0xFF94A3B8),
      onSolid: Color(0xFF0F172A),
    ),
  );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Retourne le [StatusColorSet] correspondant au [tone] donné.
  StatusColorSet statusFor(StatusPillTone tone) {
    return switch (tone) {
      StatusPillTone.success => success,
      StatusPillTone.warning => warning,
      StatusPillTone.danger => danger,
      StatusPillTone.info => info,
      StatusPillTone.neutral => neutral,
    };
  }

  // ---------------------------------------------------------------------------
  // ThemeExtension overrides
  // ---------------------------------------------------------------------------

  @override
  AppColors copyWith({
    StatusColorSet? success,
    StatusColorSet? warning,
    StatusColorSet? danger,
    StatusColorSet? info,
    StatusColorSet? neutral,
  }) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      info: info.lerp(other.info, t),
      neutral: neutral.lerp(other.neutral, t),
    );
  }
}

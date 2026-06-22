import 'package:flutter/material.dart';

/// Breakpoints responsive de l'application EasyRent.
abstract class Breakpoints {
  const Breakpoints._();

  /// Mobile : < 600px
  static const double mobile = 600;

  /// Tablette : 600px – 1023px
  static const double tablet = 1024;
}

/// Extensions sur [BuildContext] pour déterminer le type d'écran courant.
extension BreakpointContext on BuildContext {
  /// `true` si la largeur de l'écran est inférieure à [Breakpoints.mobile].
  bool get isMobile => MediaQuery.of(this).size.width < Breakpoints.mobile;

  /// `true` si la largeur de l'écran est dans la plage tablette.
  bool get isTablet =>
      MediaQuery.of(this).size.width >= Breakpoints.mobile &&
      MediaQuery.of(this).size.width < Breakpoints.tablet;

  /// `true` si la largeur de l'écran est >= [Breakpoints.tablet].
  bool get isDesktop => MediaQuery.of(this).size.width >= Breakpoints.tablet;
}

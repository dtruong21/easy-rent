import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Transitions de navigation pour EasyRent.
///
/// Sur mobile (non-web) : toujours [MaterialPage] (transitions natives OS).
/// Sur Web :
/// - [AppTransition.none]     → [NoTransitionPage] (instantané)
/// - [AppTransition.fade]     → fondu 180ms forward / 120ms reverse
/// - [AppTransition.standard] → fondu + glissement horizontal 8 px
///                              180ms forward / 120ms reverse, easeOutCubic
enum AppTransition { standard, fade, none }

/// Construit une [Page] avec la transition appropriée.
///
/// [overrideIsWeb] est réservé aux tests pour forcer le comportement web sans
/// vrai environnement web.
Page<T> appPage<T>({
  required LocalKey key,
  required Widget child,
  AppTransition transition = AppTransition.standard,
  @visibleForTesting bool? overrideIsWeb,
}) {
  final isWeb = overrideIsWeb ?? kIsWeb;

  // Sur mobile, les transitions natives Material sont meilleures que nos
  // transitions custom. On laisse Flutter choisir.
  if (!isWeb) return MaterialPage<T>(key: key, child: child);

  switch (transition) {
    case AppTransition.none:
      return NoTransitionPage<T>(key: key, child: child);

    case AppTransition.fade:
      return _buildFadePage<T>(key: key, child: child);

    case AppTransition.standard:
      return _buildStandardPage<T>(key: key, child: child);
  }
}

// ---------------------------------------------------------------------------
// Helpers privés
// ---------------------------------------------------------------------------

const Duration _kForwardDuration = Duration(milliseconds: 180);
const Duration _kReverseDuration = Duration(milliseconds: 120);
const Curve _kCurve = Curves.easeOutCubic;

/// Page avec transition fondu pur (routes auth).
Page<T> _buildFadePage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: _kForwardDuration,
    reverseTransitionDuration: _kReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: _kCurve),
        child: child,
      );
    },
  );
}

/// Page avec transition fondu + glissement horizontal 8 px (routes principales).
Page<T> _buildStandardPage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: _kForwardDuration,
    reverseTransitionDuration: _kReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: _kCurve);
      // Offset de 0.03 = glissement subtil de ~8px à 320px largeur.
      const begin = Offset(0.03, 0);
      const end = Offset.zero;
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: begin, end: end).animate(curved),
          child: child,
        ),
      );
    },
  );
}

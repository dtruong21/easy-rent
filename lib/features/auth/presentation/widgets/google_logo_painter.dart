import 'package:flutter/material.dart';

/// Logo de remplacement pour le bouton "Continuer avec Google".
///
/// **TODO (follow-up)** : remplacer par l'asset officiel Google "G" obtenu
/// depuis le Google brand resource center
/// (https://developers.google.com/identity/branding-guidelines) — au format
/// PNG `assets/auth/google_g.png` référencé dans pubspec.yaml. Une première
/// implémentation par `CustomPainter` reproduisant les arcs multicolores du
/// "G" a été retirée car elle approximait visuellement le logo, ce qui viole
/// les Google brand guidelines (toute reproduction non-officielle est
/// interdite).
///
/// En attendant l'asset officiel, on affiche un "G" monochrome en `Icons.g_mobiledata`
/// — c'est une glyphe Material générique (pas un logo Google), donc neutre
/// vis-à-vis des guidelines tout en conservant un indice visuel cohérent
/// avec l'intent du bouton.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.g_mobiledata,
      size: size,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}

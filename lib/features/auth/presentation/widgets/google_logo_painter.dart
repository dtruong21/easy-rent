import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo "G" officiel Google (multi-couleur) pour le bouton "Continuer avec
/// Google".
///
/// Le SVG inline ci-dessous est la version publiée par Google pour les
/// boutons d'identité — `viewBox 0 0 18 18`, quatre arcs de cercle dans les
/// couleurs de marque officielles (#4285F4 blue, #34A853 green, #FBBC05
/// yellow, #EA4335 red). Embedding direct (pas d'asset binaire à packager)
/// pour minimiser le poids du bundle et garantir le rendu vectoriel à toutes
/// les densités d'écran.
///
/// Référence officielle : https://developers.google.com/identity/branding-guidelines
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  // Path data identique à la publication Google. Modifier ou recolorier
  // viole les brand guidelines — toute évolution du logo doit reprendre
  // l'asset officiel à jour.
  static const String _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">'
      '<path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844c-.209 1.125-.843 2.078-1.796 2.717v2.258h2.908c1.702-1.567 2.684-3.874 2.684-6.615z"/>'
      '<path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332C2.438 15.983 5.482 18 9 18z"/>'
      '<path fill="#FBBC05" d="M3.964 10.71c-.18-.54-.282-1.117-.282-1.71s.102-1.17.282-1.71V4.958H.957C.347 6.173 0 7.548 0 9s.348 2.827.957 4.042l3.007-2.332z"/>'
      '<path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0 5.482 0 2.438 2.017.957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      semanticsLabel: 'Google',
    );
  }
}

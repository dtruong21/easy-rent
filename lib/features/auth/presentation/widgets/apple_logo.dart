import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Logo silhouette officiel Apple pour le bouton "Continuer avec Apple".
///
/// Le SVG inline ci-dessous reprend le path canonique de la silhouette Apple
/// (viewBox `0 0 384 512`), monochrome et non modifié — conformément aux
/// brand guidelines Apple (https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
/// qui exigent que le mark reste intact. La couleur est héritée du contexte
/// (encre du thème Baillan) via [ColorFilter], et non "hardcodée" en noir —
/// Apple tolère les boutons custom (hors bouton noir/blanc officiel) tant
/// que la silhouette n'est ni recolorée par morceaux, ni déformée, ni
/// recomposée.
class AppleLogo extends StatelessWidget {
  const AppleLogo({super.key, this.size = 20, this.color});

  final double size;

  /// Couleur du mark. Si `null`, hérite de `IconTheme`/`DefaultTextStyle`
  /// n'est pas applicable à un SVG — l'appelant doit donc fournir
  /// explicitement `Theme.of(context).colorScheme.onSurface` (voir
  /// [AppleSignInButton]) pour matcher le style du bouton.
  final Color? color;

  // `fill` non spécifié dans le path — flutter_svg utilise noir par défaut
  // et laisse ColorFilter.srcIn (appliqué en build) écraser la couleur avec
  // la teinte finale. On évite `fill="currentColor"` (CSS keyword sans effet
  // dans le pipeline flutter_svg) qui pourrait laisser croire à un lecteur
  // que la couleur vient de là.
  static const String _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 384 512">'
      '<path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: context.l10n.authAppleBrandName,
    );
  }
}

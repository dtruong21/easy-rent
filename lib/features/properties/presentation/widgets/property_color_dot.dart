import 'package:flutter/material.dart';

import '../../../../core/ui/theme/property_color.dart';

/// Point de couleur d'identité — décoratif, jamais seul porteur d'information
/// (le nom de l'entité reste toujours affiché à côté, cf. `property_color.dart`).
///
/// Utilisé en `leading` des cartes d'entités (bien, bail, locataire,
/// quittance) pour accélérer le repérage visuel d'un bien dans une liste.
class PropertyColorDot extends StatelessWidget {
  const PropertyColorDot({super.key, required this.colorKey, this.size = 10});

  final PropertyColorKey colorKey;

  /// Diamètre du point, en logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorKey.resolveColor(context),
      ),
    );
  }
}

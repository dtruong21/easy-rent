import 'package:flutter/material.dart';

/// Hauteur commune des boutons d'action en pied de carte d'entité.
///
/// Fixée pour deux raisons :
/// - **confort tactile** : les pieds de carte utilisaient un `styleFrom`
///   compact copié partout (`padding` vertical 6, `minimumSize: Size.zero`,
///   `tapTargetSize.shrinkWrap`) qui donnait des cibles ~28 px, désagréables au
///   doigt sur mobile ;
/// - **alignement** : boutons texte et boutons icône d'une même rangée doivent
///   partager la MÊME hauteur, sinon ils se décalent (cas des cartes de
///   quittance qui mêlaient un bouton texte et deux IconButton de tailles
///   différentes).
///
/// 40 (et non 48) évite de refaire déborder l'en-tête d'`EntityCard`, dont la
/// hauteur est dictée par le `StatusPill` — contrainte connue (cf. le menu
/// overflow compact de `lease_card`).
const double kCardActionButtonHeight = 40;

/// Bouton d'action (icône + libellé) pour les pieds de carte d'entité
/// (biens, baux, locataires, quittances).
///
/// Gabarit unique : hérite du thème `OutlinedButton` (contour olive, rayon 4)
/// et impose une hauteur commune [kCardActionButtonHeight] avec une cible
/// tactile confortable. Remplace les `OutlinedButton.styleFrom` compacts
/// dupliqués dans chaque carte.
class CardActionButton extends StatelessWidget {
  const CardActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Couleur de premier plan optionnelle (ex. action destructive).
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        minimumSize: const Size(0, kCardActionButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: Theme.of(context).textTheme.labelMedium,
        // La boîte de 40 EST la cible tactile (pas de 48 invisible qui
        // déborderait la rangée) : shrinkWrap + minimumSize.height = 40.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Bouton d'action icône seule, aligné sur [CardActionButton] (même hauteur
/// [kCardActionButtonHeight]) pour que texte et icônes d'une rangée de pied de
/// carte restent sur une seule ligne de base.
class CardActionIconButton extends StatelessWidget {
  const CardActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kCardActionButtonHeight,
      width: kCardActionButtonHeight,
      child: IconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        color: color,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

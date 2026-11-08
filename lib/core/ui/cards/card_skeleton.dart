import 'package:flutter/material.dart';

/// Squelette de chargement reproduisant la forme d'une `SummaryCard`
/// (FEAT-059) : liseré gauche, titre + sous-titre, chiffre clé à droite,
/// puis rangée basse statut + info.
///
/// Statique, sans animation shimmer. Barres en `outlineVariant` à 60 %
/// d'opacité ; surface, bordure et rayon identiques à la carte réelle pour
/// que le passage chargement → contenu ne fasse pas « sauter » la liste.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  // Mêmes mesures que SummaryCard.
  static const double _accentWidth = 4;
  static const double _padding = 12;
  static const double _rowGap = 6;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholderColor = colors.outlineVariant.withAlpha(153);
    final radius = BorderRadius.circular(12);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        _padding + _accentWidth,
        _padding - 2,
        _padding,
        _padding - 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rangée du haut : titre + sous-titre, chiffre clé à droite.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(
                      key: const Key('skeleton_title'),
                      color: placeholderColor,
                      widthFactor: 0.7,
                      height: 14,
                    ),
                    const SizedBox(height: 6),
                    _SkeletonBar(
                      color: placeholderColor,
                      widthFactor: 0.5,
                      height: 11,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                key: const Key('skeleton_key_figure'),
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _SkeletonBlock(
                    color: placeholderColor,
                    width: 64,
                    height: 16,
                  ),
                  const SizedBox(height: 4),
                  _SkeletonBlock(
                    color: placeholderColor,
                    width: 40,
                    height: 10,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: _rowGap + 4),
          // Rangée basse : pastille de statut + info secondaire.
          Row(
            children: [
              _SkeletonBlock(
                key: const Key('skeleton_status'),
                color: placeholderColor,
                width: 56,
                height: 20,
                radius: 10,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SkeletonBar(
                  color: placeholderColor,
                  widthFactor: 0.5,
                  height: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          content,
          Positioned(
            key: const Key('skeleton_accent'),
            left: 0,
            top: 0,
            bottom: 0,
            width: _accentWidth,
            child: ColoredBox(color: colors.outlineVariant),
          ),
        ],
      ),
    );
  }
}

/// Barre de largeur relative à son parent.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    super.key,
    required this.color,
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: _SkeletonBlock(color: color, height: height),
    );
  }
}

/// Bloc plein arrondi, de taille fixe (ou de la largeur de son parent).
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    super.key,
    required this.color,
    required this.height,
    this.width,
    this.radius = 4,
  });

  final Color color;
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

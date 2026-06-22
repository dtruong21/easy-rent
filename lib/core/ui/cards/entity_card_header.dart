import 'package:flutter/material.dart';

/// Widget d'en-tête réutilisable pour [EntityCard].
///
/// Disposition : [leading] + colonne ([title] + [subtitle]) + Spacer + [trailing].
class EntityCardHeader extends StatelessWidget {
  const EntityCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  /// Titre principal de la carte (obligatoire).
  final Widget title;

  /// Sous-titre optionnel affiché sous le titre.
  final Widget? subtitle;

  /// Widget affiché à gauche (icône, avatar, etc.).
  final Widget? leading;

  /// Widget affiché à droite (badge, bouton, etc.).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

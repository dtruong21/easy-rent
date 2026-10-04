import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/property_color.dart';
import 'entity_card_density.dart';

/// Carte d'entité réutilisable.
///
/// Surface à slots libres (header/body/footer). Les listes biens, baux,
/// locataires et quittances utilisent désormais `SummaryCard` (FEAT-059) ;
/// [EntityCard] reste pour les cartes de scénarios du simulateur. Supporte :
/// - Hover desktop (fond plus sombre) + InkWell ripple touch
/// - Focus ring clavier (accessibilité)
/// - Densité compact / standard
/// - Slots header, body, footer
///
/// Exemple :
/// ```dart
/// EntityCard(
///   onTap: () => context.go('/simulator'),
///   semanticLabel: 'Scénario — T2 Lyon',
///   header: Text('T2 Lyon'),
///   body: Text('Rendement net 4,2 %'),
///   footer: Row(children: [
///     FilledButton(onPressed: () {}, child: Text('Détails')),
///   ]),
/// )
/// ```
class EntityCard extends StatefulWidget {
  const EntityCard({
    super.key,
    this.header,
    this.body,
    this.footer,
    this.onTap,
    this.density = EntityCardDensity.standard,
    this.semanticLabel,
    this.accentColorKey,
  });

  /// En-tête de la carte (optionnel).
  final Widget? header;

  /// Corps principal de la carte (optionnel).
  final Widget? body;

  /// Pied de carte avec actions (optionnel).
  ///
  /// Les actions [FilledButton] / [OutlinedButton] ne propagent PAS le tap
  /// au parent [onTap] grâce au hit-testing Flutter natif.
  final Widget? footer;

  /// Callback déclenché lors d'un tap sur la carte.
  /// Si `null`, la carte n'est pas interactive.
  final VoidCallback? onTap;

  /// Densité d'affichage (compact ou standard).
  final EntityCardDensity density;

  /// Label sémantique pour les lecteurs d'écran (TalkBack / VoiceOver).
  final String? semanticLabel;

  /// Couleur d'identité du bien lié, si applicable — `null` pour les
  /// entités sans bien rattaché (ex. locataire sans bail actif). Teinte
  /// légèrement le fond de la carte (mélange avec le fond idle/hover
  /// courant, jamais la couleur brute) pour que le fond « corresponde » à
  /// l'étiquette de couleur du bien. Voir
  /// [PropertyColorKeyThemeX.resolveCardBackground] pour le calcul et les
  /// ratios de contraste mesurés.
  final PropertyColorKey? accentColorKey;

  @override
  State<EntityCard> createState() => _EntityCardState();
}

class _EntityCardState extends State<EntityCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    final padding = widget.density.padding;
    final gap = widget.density.gap;

    final baseBgColor = _isHovered
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow;
    final accentColorKey = widget.accentColorKey;
    final bgColor = accentColorKey != null
        ? accentColorKey.resolveCardBackground(context, baseBgColor)
        : baseBgColor;

    final borderColor = _isFocused
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final borderWidth = _isFocused ? 2.0 : 1.0;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            if (widget.body != null) ...[SizedBox(height: gap), widget.body!],
            if (widget.footer != null) ...[
              SizedBox(height: gap),
              widget.footer!,
            ],
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: Semantics(
            label: widget.semanticLabel,
            button: true,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(radii.md),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(radii.md),
                child: card,
              ),
            ),
          ),
        ),
      );
    } else if (widget.semanticLabel != null) {
      card = Semantics(label: widget.semanticLabel, child: card);
    }

    return card;
  }
}

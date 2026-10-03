import 'package:flutter/material.dart';

import '../../i18n/l10n_extensions.dart';

/// Chiffre clé affiché en gros à droite d'une [SummaryCard].
class SummaryKeyFigure {
  const SummaryKeyFigure({required this.value, this.caption});

  /// Valeur formatée (ex. « 800,00 € »).
  final String value;

  /// Légende sous la valeur (ex. « CC / mois »).
  final String? caption;
}

/// Entrée du menu ⋮ d'une [SummaryCard].
class SummaryMenuItem {
  const SummaryMenuItem({
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.key,
  });

  final String label;
  final VoidCallback onSelected;

  /// Action destructive (ex. annuler une quittance) : texte couleur `error`.
  final bool destructive;

  /// Clé posée sur le `PopupMenuItem` (tests).
  final Key? key;
}

/// Bouton compact de l'action rapide d'une [SummaryCard].
///
/// Une seule action rapide par carte : la plus fréquente pour l'entité.
/// `onPressed == null` → bouton désactivé (le [tooltip] explique pourquoi).
class SummaryQuickActionButton extends StatelessWidget {
  const SummaryQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Carte de liste « chiffre clé » (spec 2026-09-29).
///
/// ```
/// ┌▌ Titre                      800 €  ⋮ ┐
/// │▌ Sous-titre                CC / mois │
/// └▌ [statut]  info           [Action]   ┘
/// ```
///
/// Présentation pure : aucun import de feature. Les adaptateurs de chaque
/// feature (`PropertyCard`, `LeaseCard`, …) lui passent des chaînes déjà
/// localisées et des callbacks existants.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    this.subtitle,
    this.accentColor,
    this.keyFigure,
    this.status,
    this.meta,
    this.quickAction,
    this.menuItems = const [],
    this.menuKey,
    this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// Couleur du liseré gauche (couleur du bien). `null` → `outlineVariant`.
  final Color? accentColor;

  /// Chiffre clé en haut à droite. Absent → l'action rapide prend sa place.
  final SummaryKeyFigure? keyFigure;

  /// Pastille de statut (typiquement un `StatusPill` taille sm).
  final Widget? status;

  /// Information secondaire de la rangée basse (1 ligne, ellipsis).
  final String? meta;

  /// Action rapide (typiquement un [SummaryQuickActionButton]).
  final Widget? quickAction;

  /// Entrées du menu ⋮ — menu masqué si vide.
  final List<SummaryMenuItem> menuItems;

  /// Clé du bouton ⋮ (tests).
  final Key? menuKey;

  final VoidCallback? onTap;
  final String? semanticLabel;

  static const double _accentWidth = 4;
  static const double _padding = 12;
  static const double _rowGap = 6;

  /// Part maximale de la rangée du haut laissée au chiffre clé. Au-delà, le
  /// montant est réduit à l'échelle (jamais tronqué) : un montant géant ou une
  /// police plus large (CI Linux) ne peut plus faire déborder la carte.
  static const double _keyFigureMaxWidthFactor = 0.45;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(12);

    final hasKeyFigure = keyFigure != null;
    final topAction = hasKeyFigure ? null : quickAction;
    final bottomAction = hasKeyFigure ? quickAction : null;
    final hasBottomRow =
        status != null || (meta?.isNotEmpty ?? false) || bottomAction != null;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        _padding + _accentWidth,
        _padding - 2,
        _padding - 4,
        _padding - 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasKeyFigure) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.hasBoundedWidth
                          ? constraints.maxWidth * _keyFigureMaxWidthFactor
                          : double.infinity,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            keyFigure!.value,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (keyFigure!.caption != null)
                            Text(
                              keyFigure!.caption!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (topAction != null) ...[
                  const SizedBox(width: 8),
                  _ActionSlot(child: topAction),
                ],
                if (menuItems.isNotEmpty) _buildMenu(context),
              ],
            ),
          ),
          if (hasBottomRow) ...[
            const SizedBox(height: _rowGap),
            Row(
              children: [
                if (status != null) ...[status!, const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    meta ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (bottomAction != null) ...[
                  const SizedBox(width: 8),
                  _ActionSlot(child: bottomAction),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              content,
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _accentWidth,
                child: ColoredBox(color: accentColor ?? colors.outlineVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<int>(
      key: menuKey,
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: context.l10n.commonMoreActions,
      onSelected: (i) => menuItems[i].onSelected(),
      itemBuilder: (_) => [
        for (var i = 0; i < menuItems.length; i++)
          PopupMenuItem<int>(
            key: menuItems[i].key,
            value: i,
            child: Text(
              menuItems[i].label,
              style: menuItems[i].destructive ? TextStyle(color: error) : null,
            ),
          ),
      ],
    );
  }
}

/// Emplacement de l'action rapide : partage l'espace avec l'info voisine
/// (comme avant) mais cale l'action à DROITE de son emplacement.
///
/// Sans l'`Align`, un `Flexible` seul plaçait l'action au début de sa moitié
/// de rangée : sur une carte large elle flottait au milieu (recette web
/// 2026-09-29).
class _ActionSlot extends StatelessWidget {
  const _ActionSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Align(alignment: Alignment.centerRight, child: child),
  );
}

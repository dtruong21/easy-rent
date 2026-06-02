import 'package:flutter/material.dart';

/// Carte KPI générique du dashboard.
///
/// Affiche une métrique avec icône, label, valeur principale et un subtitle
/// optionnel. La [semanticColor] colorise la valeur (ex: rouge pour retards).
///
/// Le slot [child] permet d'insérer un mini-chart en P1 (aujourd'hui vide).
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.semanticColor,
    this.onTap,
    this.child,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  /// Couleur sémantique appliquée à la valeur et à l'icône wrap.
  final Color? semanticColor;

  /// Navigation optionnelle au tap.
  final VoidCallback? onTap;

  /// Slot pour contenu additionnel (mini-chart P1).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = semanticColor ?? theme.colorScheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (child != null) ...[const SizedBox(height: 8), child!],
            ],
          ),
        ),
      ),
    );
  }
}

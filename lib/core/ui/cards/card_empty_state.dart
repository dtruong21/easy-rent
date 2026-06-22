import 'package:flutter/material.dart';

/// État vide pour une liste ou grille de cartes.
///
/// Affiche une icône, un titre, un message et une action optionnelle.
///
/// Exemple :
/// ```dart
/// CardEmptyState(
///   icon: Icons.home_outlined,
///   title: 'Aucun bien',
///   message: 'Ajoutez votre premier bien pour commencer.',
///   action: FilledButton(
///     onPressed: () => context.go('/properties/new'),
///     child: Text('Ajouter un bien'),
///   ),
/// )
/// ```
class CardEmptyState extends StatelessWidget {
  const CardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  /// Icône illustrant l'état vide.
  final IconData icon;

  /// Titre court (ex : "Aucun bien").
  final String title;

  /// Message explicatif pour l'utilisateur.
  final String message;

  /// Action optionnelle (bouton "Ajouter", etc.).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

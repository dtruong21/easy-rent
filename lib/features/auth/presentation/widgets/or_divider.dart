import 'package:flutter/material.dart';

/// Séparateur horizontal avec un libellé centré (typiquement "ou").
///
/// Utilisé entre le bloc email/mot de passe et le bouton de connexion
/// Google sur les pages `/login` et `/signup`.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'ou'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: color, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          Expanded(child: Divider(color: color, thickness: 1)),
        ],
      ),
    );
  }
}

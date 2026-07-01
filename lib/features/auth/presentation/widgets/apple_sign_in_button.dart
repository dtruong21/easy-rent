import 'package:flutter/material.dart';

import 'apple_logo.dart';

/// Bouton "Continuer avec Apple".
///
/// Même style que [GoogleSignInButton] (OutlinedButton secondaire, thème
/// Baillan papier/encre) — Apple tolère les boutons custom tant que la
/// silhouette du mark reste intacte (voir [AppleLogo]). On n'utilise donc
/// PAS le bouton noir/blanc officiel Apple, par cohérence visuelle avec le
/// bouton Google déjà en place.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    this.label = 'Continuer avec Apple',
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: (isLoading || onPressed == null) ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(color: theme.colorScheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: isLoading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppleLogo(size: 20, color: theme.colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import 'google_logo_painter.dart';

/// Bouton "Continuer avec Google".
///
/// Respecte le thème Baillan (OutlinedButton secondaire, jamais le bleu
/// Material par défaut — l'olive reste réservé au [FilledButton] primaire)
/// tout en conservant l'identité visuelle Google (logo "G" multicolore,
/// hauteur 48px conforme aux brand guidelines).
///
/// [label] est nullable : `null` (défaut) résout
/// `context.l10n.authContinueWithGoogleButton` au build.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    this.label,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedLabel = label ?? context.l10n.authContinueWithGoogleButton;
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
                  const GoogleLogo(size: 20),
                  const SizedBox(width: 12),
                  Text(
                    resolvedLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// AppBar réutilisable Baillan.
///
/// Gère automatiquement le bouton retour selon le contexte :
/// - Si [leading] fourni → override total
/// - Si [showBackButton] == false → pas de leading
/// - Si [Navigator.canPop] → [BackButton] Material (pop natif)
/// - Sinon si [fallbackRoute] fourni → [IconButton] avec [Icons.arrow_back]
///   et Key `'app_bar_back'` pour la testabilité
/// - Sinon → leading null (comportement AppBar par défaut)
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    required this.title,
    this.fallbackRoute,
    this.actions,
    this.leading,
    this.showBackButton = true,
    this.bottom,
  });

  /// Titre affiché dans l'AppBar.
  final String title;

  /// Route de fallback si [Navigator.canPop] est false.
  /// Utilisée via [GoRouter.go] pour une navigation déclarative.
  final String? fallbackRoute;

  /// Boutons d'action côté droit.
  final List<Widget>? actions;

  /// Widget leading custom — override total (ignore [showBackButton] et
  /// [fallbackRoute]).
  final Widget? leading;

  /// Si false, aucun leading n'est produit, même si [Navigator.canPop].
  final bool showBackButton;

  /// TabBar ou autre widget sous la barre de titre.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final extra = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + extra);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedLeading = _resolveLeading(context);
    return AppBar(
      title: Text(title),
      // On prend entièrement en charge le leading via _resolveLeading.
      // En désactivant l'implication automatique, AppBar ne peut pas insérer
      // son propre BackButton — ce qui garantit que showBackButton: false
      // supprime bien le bouton retour même quand Navigator.canPop est true.
      automaticallyImplyLeading: false,
      leading: resolvedLeading,
      actions: actions,
      bottom: bottom,
    );
  }

  Widget? _resolveLeading(BuildContext context) {
    // Override total : leading fourni explicitement.
    if (leading != null) return leading;

    // Pas de bouton retour souhaité.
    if (!showBackButton) return null;

    // Retour natif via Navigator (canPop).
    if (Navigator.canPop(context)) {
      return BackButton(
        key: const Key('app_bar_back'),
        onPressed: () => Navigator.pop(context),
      );
    }

    // Fallback déclaratif via GoRouter.
    if (fallbackRoute != null) {
      return IconButton(
        key: const Key('app_bar_back'),
        icon: const Icon(Icons.arrow_back),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => context.go(fallbackRoute!),
      );
    }

    return null;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/store_billing_models.dart';
import '../../domain/store_names.dart';
import '../pro_pricing_copy.dart';

/// Vues sans état de l'écran d'achat des apps (FEAT-044e) — voir
/// `ProStorePaywall`. Aucune n'affiche de prix web, de palier Max/Ultra ni de
/// lien vers le site (App Store 3.1.1, Paiements Google Play).

/// Contenu centré, 560 px de large au plus, défilant si l'écran est court.
class _StoreLayout extends StatelessWidget {
  const _StoreLayout({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Formules Pro du store (annuel puis mensuel), « Restaurer » et mentions
/// légales. Les boutons sont inactifs pendant un achat ([busy]).
class StoreOffersView extends StatelessWidget {
  const StoreOffersView({
    super.key,
    required this.offer,
    required this.busy,
    required this.onBuy,
    required this.onRestore,
  });

  final ProStoreOffer offer;
  final bool busy;
  final void Function(ProStorePackage package) onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final annual = offer.annual;
    final monthly = offer.monthly;
    return _StoreLayout(
      children: [
        Text(
          l10n.storePaywallHeadline,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          proPricingTaglineFor(context, 'pro'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final bullet in proPricingBulletsFor(context, 'pro'))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(bullet)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (annual != null) ...[
          FilledButton(
            key: const Key('btn_store_buy_annual'),
            onPressed: busy ? null : () => onBuy(annual),
            child: Text(l10n.storeBuyAnnualButton(annual.priceString)),
          ),
          const SizedBox(height: 12),
        ],
        if (monthly != null) ...[
          OutlinedButton(
            key: const Key('btn_store_buy_monthly'),
            onPressed: busy ? null : () => onBuy(monthly),
            child: Text(l10n.storeBuyMonthlyButton(monthly.priceString)),
          ),
          const SizedBox(height: 12),
        ],
        TextButton(
          key: const Key('btn_store_restore'),
          onPressed: busy ? null : onRestore,
          child: Text(l10n.storeRestoreButton),
        ),
        const SizedBox(height: 16),
        const StoreLegalNotice(),
      ],
    );
  }
}

/// Mentions App Store 3.1.2 : renouvellement automatique, résiliation dans
/// les réglages du store, liens vers les conditions et la confidentialité.
class StoreLegalNotice extends StatelessWidget {
  const StoreLegalNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.storeLegalNotice(storeNameForPlatform(defaultTargetPlatform)),
          key: const Key('txt_store_legal_notice'),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const Key('link_store_terms'),
              onPressed: () => context.push('/terms'),
              child: Text(l10n.storeTermsLink),
            ),
            TextButton(
              key: const Key('link_store_privacy'),
              onPressed: () => context.push('/privacy'),
              child: Text(l10n.storePrivacyLink),
            ),
          ],
        ),
      ],
    );
  }
}

/// Achat ou restauration réussis, droit pas encore reçu du serveur.
class StoreActivatingView extends StatelessWidget {
  const StoreActivatingView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return _StoreLayout(
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(
          l10n.storeActivatingTitle,
          key: const Key('txt_store_activating'),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.storeActivatingBody,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Activation au-delà de `kStoreActivationTimeout` : rassure, propose de
/// restaurer ou de relancer l'attente — jamais un second achat.
class StoreActivationDelayedView extends StatelessWidget {
  const StoreActivationDelayedView({
    super.key,
    required this.busy,
    required this.onRestore,
    required this.onRetry,
  });

  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StoreLayout(
      children: [
        Text(
          l10n.storeActivationDelayedBody,
          key: const Key('txt_store_activation_delayed'),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          key: const Key('btn_store_activation_retry'),
          onPressed: busy ? null : onRetry,
          child: Text(l10n.commonRetry),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('btn_store_activation_restore'),
          onPressed: busy ? null : onRestore,
          child: Text(l10n.storeRestoreButton),
        ),
      ],
    );
  }
}

/// Compte déjà Pro (ou plus), quelle que soit l'origine : aucun achat.
class StoreAlreadySubscribedView extends StatelessWidget {
  const StoreAlreadySubscribedView({super.key, required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return _StoreLayout(
      children: [
        Icon(
          Icons.verified_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.storeAlreadySubscribed,
          key: const Key('txt_store_already_subscribed'),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          key: const Key('btn_store_manage_subscription'),
          onPressed: onManage,
          child: Text(l10n.storeManageSubscriptionButton),
        ),
      ],
    );
  }
}

/// Offre du store introuvable : message et nouvelle tentative.
class StoreOfferUnavailableView extends StatelessWidget {
  const StoreOfferUnavailableView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StoreLayout(
      children: [
        Text(
          l10n.storeOfferUnavailable,
          key: const Key('txt_store_offer_unavailable'),
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          key: const Key('btn_store_offer_retry'),
          onPressed: onRetry,
          child: Text(l10n.commonRetry),
        ),
      ],
    );
  }
}

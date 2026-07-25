import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/subscription_tier.dart';
import '../application/checkout_controller.dart';
import '../application/paid_plan_interest_controller.dart';

/// Page `/pro` — pricing Baillan Pro.
///
/// **Gating freemium (MVP, juillet 2026)** : tant que
/// [Env.subscriptionsEnabled] vaut `false` (défaut), le checkout Stripe est
/// masqué — [_PriceCard] affiche un état « bientôt disponible » + capture
/// d'intérêt ([paidPlanInterestControllerProvider]) à la place du bouton
/// « S'abonner ». Cette page reste volontairement atteignable (upsells
/// verrouillés du simulateur, tuile Profil) : jamais d'impasse. Repasser
/// [Env.subscriptionsEnabled] à `true` restaure le checkout Stripe sans
/// aucun autre changement de code.
class ProPricingPage extends ConsumerStatefulWidget {
  const ProPricingPage({super.key});

  @override
  ConsumerState<ProPricingPage> createState() => _ProPricingPageState();
}

class _ProPricingPageState extends ConsumerState<ProPricingPage> {
  bool _annual = false;
  bool _isLoading = false;
  bool _isNotifying = false;
  bool _notified = false;

  Future<void> _checkout() async {
    setState(() => _isLoading = true);
    final plan = _annual ? 'annual' : 'monthly';
    final url = await ref
        .read(checkoutControllerProvider.notifier)
        .startCheckout(plan: plan);

    if (!mounted) return;
    if (url != null) {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.proCheckoutError)));
    }
  }

  // NB : le contrôleur passe par AsyncValue.guard — il ne throw JAMAIS,
  // l'échec atterrit dans son state (même politique que
  // ComingSoonPaidPlanSection._notifyMe).
  Future<void> _notifyMe() async {
    setState(() => _isNotifying = true);
    await ref
        .read(paidPlanInterestControllerProvider.notifier)
        .notifyMe(features: const [proPricingInterestKey]);
    if (!mounted) return;

    if (ref.read(paidPlanInterestControllerProvider).hasError) {
      setState(() => _isNotifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.proInterestSaveErrorSnackbar)),
      );
      return;
    }

    setState(() {
      _isNotifying = false;
      _notified = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tierSnapshot = ref.watch(landlordTierProvider).valueOrNull;
    final isPaid = tierSnapshot?.tier == SubscriptionTier.paid;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.proPricingTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.proPricingHeadline,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.proPricingSubheadline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Plan toggle
                _PlanToggle(
                  annual: _annual,
                  onChanged: (v) => setState(() => _annual = v),
                ),
                const SizedBox(height: 24),

                // Price card
                _PriceCard(
                  annual: _annual,
                  isPaid: isPaid,
                  isLoading: _isLoading,
                  onCheckout: isPaid ? null : _checkout,
                  isNotifying: _isNotifying,
                  notified: _notified,
                  onNotifyMe: _notifyMe,
                ),
                const SizedBox(height: 24),

                // Features list
                _FeaturesList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanToggle extends StatelessWidget {
  const _PlanToggle({required this.annual, required this.onChanged});

  final bool annual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.proPlanMonthly,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: annual ? FontWeight.normal : FontWeight.bold,
            color: annual ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(value: annual, onChanged: onChanged),
        const SizedBox(width: 8),
        Text(
          l10n.proPlanAnnual,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: annual ? FontWeight.bold : FontWeight.normal,
            color: annual ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.annual,
    required this.isPaid,
    required this.isLoading,
    required this.onCheckout,
    required this.isNotifying,
    required this.notified,
    required this.onNotifyMe,
  });

  final bool annual;
  final bool isPaid;
  final bool isLoading;
  final VoidCallback? onCheckout;

  /// Bloc « bientôt disponible » (`Env.subscriptionsEnabled == false`).
  final bool isNotifying;
  final bool notified;
  final VoidCallback onNotifyMe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final price = annual ? '79' : '7,99';
    final period = annual ? l10n.proPeriodYear : l10n.proPeriodMonth;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Text(
              'Baillan Pro',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: theme.textTheme.displaySmall,
                children: [
                  TextSpan(
                    text: '$price €',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: ' / $period',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (annual) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.proAnnualSaving,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (isPaid)
              FilledButton.tonal(
                onPressed: null,
                child: Text(l10n.proAlreadySubscribed),
              )
            else if (!Env.subscriptionsEnabled)
              _ComingSoonNotify(
                isLoading: isNotifying,
                notified: notified,
                onNotifyMe: onNotifyMe,
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('btn_pro_subscribe'),
                  onPressed: isLoading ? null : onCheckout,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.proSubscribeButton),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// État « bientôt disponible » de [_PriceCard] — remplace le bouton Stripe
/// tant que [Env.subscriptionsEnabled] vaut `false` (freemium MVP). Réutilise
/// [paidPlanInterestControllerProvider] (même mécanisme que
/// `ComingSoonPaidPlanSection`, pied de `/simulator`).
class _ComingSoonNotify extends StatelessWidget {
  const _ComingSoonNotify({
    required this.isLoading,
    required this.notified,
    required this.onNotifyMe,
  });

  final bool isLoading;
  final bool notified;
  final VoidCallback onNotifyMe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            l10n.proComingSoonBadge,
            key: const Key('txt_pro_coming_soon_badge'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.proSubscriptionsPausedNotice,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            key: const Key('btn_pro_notify_me'),
            onPressed: (isLoading || notified) ? null : onNotifyMe,
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    notified
                        ? l10n.proNotifiedButtonLabel
                        : l10n.proNotifyMeButton,
                  ),
          ),
        ),
      ],
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final features = [
      l10n.proFeatureUnlimitedProperties,
      l10n.proFeatureUnlimitedLeases,
      l10n.proFeatureUnlimitedTenants,
      l10n.proFeatureUnlimitedDocuments,
      l10n.proFeatureUnlimitedScenarios,
      l10n.proFeaturePriority,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.proFeaturesTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final feature in features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(feature)),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/subscription_tier.dart';
import '../application/checkout_controller.dart';

class ProPricingPage extends ConsumerStatefulWidget {
  const ProPricingPage({super.key});

  @override
  ConsumerState<ProPricingPage> createState() => _ProPricingPageState();
}

class _ProPricingPageState extends ConsumerState<ProPricingPage> {
  bool _annual = false;
  bool _isLoading = false;

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
  });

  final bool annual;
  final bool isPaid;
  final bool isLoading;
  final VoidCallback? onCheckout;

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
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
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

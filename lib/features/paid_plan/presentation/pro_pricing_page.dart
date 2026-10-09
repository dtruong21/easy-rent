import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/breakpoints.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_entitlement.dart';
import '../../auth/domain/plan_level.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../../auth/domain/subscription_tier.dart';
import '../application/checkout_controller.dart';
import '../application/current_billing_period_provider.dart';
import '../application/paid_plan_interest_controller.dart';
import '../application/plan_change_controller.dart';
import '../data/checkout_repository.dart';
import '../data/subscription_repository.dart';
import 'pro_pricing_copy.dart';
import 'pro_pricing_cta.dart';
import 'widgets/plan_card.dart';
import 'widgets/plan_change_dialog.dart';
import 'widgets/plan_comparison_table.dart';
import 'widgets/plan_level_label.dart';

/// Page `/pro` — 4 offres (Gratuit, Pro, Max, Ultra), FEAT-056 PR-6.
///
/// **Seul Pro est achetable.** Max et Ultra s'affichent en « bientôt
/// disponible » (badge + prix indicatif + capture d'intérêt taguée par
/// palier) dès que [PlanLevelSpec.purchasable] vaut `false` — propriété lue
/// dans la table générée, jamais déduite du nom du palier. Le gate global
/// [Env.subscriptionsEnabled] prime sur `purchasable` : à `false`, les 3
/// cartes payantes passent en « bientôt disponible », Pro inclus (freemium
/// MVP, cf. `docs/ENVIRONMENTS.md`).
///
/// Aucun chemin de paiement (checkout ni changement de palier) n'est jamais
/// rendu pour un palier non `purchasable` — testé par
/// `test/widget/pro_pricing_page_test.dart`.
///
/// **Apps iOS/Android** ([isStoreApp]) : ni offres, ni prix, ni bouton — un
/// message neutre. App Store 3.1.1 et la règle Paiements de Google Play
/// interdisent tout achat hors achat intégré, et toute incitation à acheter
/// ailleurs (donc aucune mention du site web). L'achat intégré viendra se
/// brancher sur ce même garde-fou.
class ProPricingPage extends ConsumerStatefulWidget {
  const ProPricingPage({super.key});

  @override
  ConsumerState<ProPricingPage> createState() => _ProPricingPageState();
}

class _ProPricingPageState extends ConsumerState<ProPricingPage> {
  bool _annual = false;
  final Map<String, bool> _notifying = {};
  final Set<String> _notified = {};
  final Set<String> _checkoutLoading = {};
  bool _planChangeLoading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isStoreApp) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.proPricingTitle)),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.proStoreAppUnavailable,
                key: const Key('txt_pro_store_app_unavailable'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final plan = ref.watch(planEntitlementProvider);
    final snapshot = ref.watch(landlordTierProvider).valueOrNull;
    final period = _annual ? 'annual' : 'monthly';
    // Périodicité facturée : lue (Stripe) uniquement pour un abonné web payant
    // et la vente ouverte. Inconnue / en cours / en erreur → `null`, donc pas
    // de bouton de passage mensuel ↔ annuel.
    final currentPeriod =
        Env.subscriptionsEnabled &&
            plan.tier == SubscriptionTier.paid &&
            !mobileStores.contains(snapshot?.proStore)
        ? ref.watch(currentBillingPeriodProvider).valueOrNull
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.proPricingTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= Breakpoints.tablet;
            final cards = _buildCards(
              context,
              plan,
              snapshot,
              period,
              currentPeriod,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.proPricingHeadline,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.proPricingSubheadline,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: _PlanToggle(
                      annual: _annual,
                      onChanged: (v) => setState(() => _annual = v),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _CardsGrid(maxWidth: constraints.maxWidth, cards: cards),
                  if (isDesktop) ...[
                    const SizedBox(height: 32),
                    Text(
                      l10n.proPricingCompareTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const PlanComparisonTable(),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    l10n.proPricingFooter,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Construction des cartes
  // ---------------------------------------------------------------------

  List<Widget> _buildCards(
    BuildContext context,
    PlanEntitlement plan,
    LandlordTierSnapshot? snapshot,
    String period,
    String? currentPeriod,
  ) {
    final l10n = context.l10n;
    final freeCard = PlanCard(
      key: const Key('plan_card_free'),
      title: l10n.planLevelFree,
      tagline: l10n.proPricingFreeTagline,
      bullets: proPricingFreeBullets(context),
      cta: buildFreeCta(context, plan),
    );
    final paidCards = [
      for (final spec in PlanMatrix.levels)
        PlanCard(
          key: Key('plan_card_${spec.id}'),
          title: planLevelLabelForId(context, spec.id),
          tagline: proPricingTaglineFor(context, spec.id),
          bullets: proPricingBulletsFor(context, spec.id),
          priceLabel: _annual ? spec.priceLabelAnnual : spec.priceLabelMonthly,
          priceIndicativeSuffix: spec.priceIndicative
              ? l10n.proPricingIndicativeSuffix
              : null,
          recommended: spec.recommended,
          recommendedLabel: l10n.planRecommendedBadge,
          badge: buildComingSoonBadge(context, plan, spec),
          cta: buildPaidLevelCta(
            context,
            plan: plan,
            proStore: snapshot?.proStore,
            spec: spec,
            checkoutLoading: _checkoutLoading.contains(spec.id),
            planChangeLoading: _planChangeLoading,
            notifyLoading: _notifying[spec.id] ?? false,
            notified: _notified.contains(spec.id),
            annual: _annual,
            currentPeriod: currentPeriod,
            onCheckout: () => _onCheckout(context, spec.id, period),
            onChangePlan: (isUpgrade) => _onChangePlan(
              context,
              PlanLevel.values.firstWhere((l) => l.id == spec.id),
              period,
              isUpgrade,
            ),
            onSwitchPeriod: () => _onSwitchPeriod(context, spec, period),
            onNotifyMe: () => _onNotifyMe(spec.id),
          ),
        ),
    ];
    return [freeCard, ...paidCards];
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _onCheckout(
    BuildContext context,
    String levelId,
    String period,
  ) async {
    setState(() => _checkoutLoading.add(levelId));
    final url = await ref
        .read(checkoutControllerProvider.notifier)
        .startCheckout(level: levelId, period: period);
    if (!context.mounted) return;
    if (url != null) {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
      return;
    }
    setState(() => _checkoutLoading.remove(levelId));
    final error = ref.read(checkoutControllerProvider).error;
    _showSnackBar(context, _checkoutErrorMessage(context, error));
  }

  String _checkoutErrorMessage(BuildContext context, Object? error) {
    final l10n = context.l10n;
    return switch (error) {
      AlreadySubscribedException() => l10n.proCheckoutErrorAlreadySubscribed,
      LevelNotPurchasableException() => l10n.proPlanNotAvailableError,
      PriceNotConfiguredException() => l10n.proPlanNotAvailableError,
      _ => l10n.proCheckoutError,
    };
  }

  /// Même palier, autre périodicité (mensuel ↔ annuel) : un `change_plan`
  /// comme un autre, seul le texte de confirmation change.
  Future<void> _onSwitchPeriod(
    BuildContext context,
    PlanLevelSpec spec,
    String period,
  ) {
    final level = PlanLevel.values.firstWhere((l) => l.id == spec.id);
    final label = level.label(context);
    final l10n = context.l10n;
    return _onChangePlan(
      context,
      level,
      period,
      false,
      dialogBody: period == 'annual'
          ? l10n.planSwitchToAnnualBody(label, spec.priceLabelAnnual)
          : l10n.planSwitchToMonthlyBody(label, spec.priceLabelMonthly),
    );
  }

  Future<void> _onChangePlan(
    BuildContext context,
    PlanLevel level,
    String period,
    bool isUpgrade, {
    String? dialogBody,
  }) async {
    final confirmed = await showPlanChangeDialog(
      context,
      targetLevelLabel: level.label(context),
      isUpgrade: isUpgrade,
      body: dialogBody,
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _planChangeLoading = true);
    final ok = await ref
        .read(planChangeControllerProvider.notifier)
        .changePlan(level: level.id, period: period);
    if (!context.mounted) return;
    setState(() => _planChangeLoading = false);

    final l10n = context.l10n;
    if (ok) {
      // Stripe applique le prix tout de suite : relire la périodicité masque
      // le bouton de passage sans attendre le webhook.
      ref.invalidate(currentBillingPeriodProvider);
      _showSnackBar(
        context,
        l10n.planChangeSuccess,
        key: 'snackbar_plan_change_success',
      );
      return;
    }
    final error = ref.read(planChangeControllerProvider).error;
    final message = switch (error) {
      NoActiveWebSubscriptionException() => l10n.subscriptionErrorNoWebSub,
      PriceNotConfiguredException() => l10n.proPlanNotAvailableError,
      LevelNotPurchasableException() => l10n.proPlanNotAvailableError,
      _ => l10n.subscriptionErrorGeneric,
    };
    _showSnackBar(context, message, key: 'snackbar_plan_change_error');
  }

  // NB : le contrôleur passe par AsyncValue.guard — il ne throw JAMAIS,
  // l'échec atterrit dans son state (même politique que
  // ComingSoonPaidPlanSection._notifyMe / l'ancien _ProPricingPageState).
  Future<void> _onNotifyMe(String levelId) async {
    setState(() => _notifying[levelId] = true);
    await ref
        .read(paidPlanInterestControllerProvider.notifier)
        .notifyMe(features: [proPricingInterestKeyFor(levelId)]);
    if (!mounted) return;

    if (ref.read(paidPlanInterestControllerProvider).hasError) {
      setState(() => _notifying[levelId] = false);
      _showSnackBar(context, context.l10n.proInterestSaveErrorSnackbar);
      return;
    }
    setState(() {
      _notifying[levelId] = false;
      _notified.add(levelId);
    });
  }

  void _showSnackBar(BuildContext context, String message, {String? key}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(key: key != null ? Key(key) : null, content: Text(message)),
    );
  }
}

/// Toggle mensuel/annuel unique pour les 3 offres payantes (comportement
/// inchangé depuis FEAT-044e — un seul toggle, jamais un par carte).
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
        Switch.adaptive(
          key: const Key('switch_plan_period'),
          value: annual,
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Text(
          l10n.proPlanAnnual,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: annual ? FontWeight.bold : FontWeight.normal,
            color: annual ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (annual) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l10n.proAnnualSaving,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Grille responsive des 4 cartes (FEAT-056 §8.1, patron FEAT-055 —
/// `scenario_comparison_page.dart`) :
/// - `< Breakpoints.mobile` (600) : colonne pleine largeur.
/// - `Breakpoints.mobile – Breakpoints.tablet` (600–1024) : 2 colonnes.
/// - `>= Breakpoints.tablet` (1024) : ligne de 4 cartes de largeur égale.
class _CardsGrid extends StatelessWidget {
  const _CardsGrid({required this.maxWidth, required this.cards});

  final double maxWidth;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    const spacing = 16.0;

    if (maxWidth < Breakpoints.mobile) {
      return Column(
        children: [
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: spacing),
              child: card,
            ),
        ],
      );
    }

    if (maxWidth < Breakpoints.tablet) {
      final columnWidth = (maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final card in cards) SizedBox(width: columnWidth, child: card),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final card in cards)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: spacing / 2),
                child: card,
              ),
            ),
        ],
      ),
    );
  }
}

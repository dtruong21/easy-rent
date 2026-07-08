import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/domain/subscription_tier.dart';
import '../../../paid_plan/application/paid_plan_interest_controller.dart';

/// Fonctionnalités Plan Pro proposées au clic « M'avertir du lancement »
/// depuis la modal limite FREE. Miroir de [ComingSoonPaidPlanSection].
const List<String> _paidPlanFeatures = [
  'comparateur',
  'sensibilite_taux',
  'fiscal_lmnp',
  'export_pdf',
];

/// Affiche la modal bloquante de limite de scénarios atteinte.
///
/// - `tier == anonymous` : CTA « Créer un compte » (jusqu'à 3 scénarios).
/// - `tier == free` : CTA « M'avertir du lancement » (Plan Pro, pas encore
///   disponible) — écrit `paid_plan_interest/{uid}` via
///   [PaidPlanInterestController].
Future<void> showScenarioLimitReachedModal(
  BuildContext context, {
  required SubscriptionTier tier,
}) {
  assert(
    tier != SubscriptionTier.paid,
    'showScenarioLimitReachedModal ne doit jamais être appelée pour un '
    'tier paid (illimité — canSaveAnotherScenarioProvider est déjà true).',
  );
  return showDialog<void>(
    context: context,
    builder: (context) => _ScenarioLimitReachedDialog(tier: tier),
  );
}

class _ScenarioLimitReachedDialog extends ConsumerWidget {
  const _ScenarioLimitReachedDialog({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnonymous = tier == SubscriptionTier.anonymous;
    final l10n = context.l10n;

    return AlertDialog(
      key: const Key('scenario_limit_reached_modal'),
      title: Text(
        isAnonymous
            ? l10n.simulatorLimitReachedTitleAnonymous
            : l10n.simulatorLimitReachedTitleFree,
      ),
      content: Text(
        isAnonymous
            ? l10n.simulatorLimitReachedContentAnonymous
            : l10n.simulatorLimitReachedContentFree,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.simulatorLimitReachedLaterButton),
        ),
        if (isAnonymous)
          FilledButton(
            key: const Key('scenario_limit_signup_cta'),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/signup');
            },
            child: Text(l10n.simulatorLimitReachedSignupButton),
          )
        else
          _NotifyMeButton(onSubmitted: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _NotifyMeButton extends ConsumerStatefulWidget {
  const _NotifyMeButton({required this.onSubmitted});

  final VoidCallback onSubmitted;

  @override
  ConsumerState<_NotifyMeButton> createState() => _NotifyMeButtonState();
}

class _NotifyMeButtonState extends ConsumerState<_NotifyMeButton> {
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    await ref
        .read(paidPlanInterestControllerProvider.notifier)
        .notifyMe(features: _paidPlanFeatures);
    if (!mounted) return;

    // Le contrôleur ne throw jamais (AsyncValue.guard) : relire son state.
    // Erreur → pas de faux succès, le bouton redevient cliquable.
    if (ref.read(paidPlanInterestControllerProvider).hasError) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.simulatorInterestSaveErrorSnackbar),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.simulatorLimitReachedNotifyMeSuccessSnackbar,
        ),
      ),
    );
    widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const Key('scenario_limit_notify_cta'),
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(context.l10n.simulatorNotifyMeButton),
    );
  }
}

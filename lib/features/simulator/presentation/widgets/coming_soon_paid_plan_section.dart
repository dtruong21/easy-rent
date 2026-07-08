import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../paid_plan/application/paid_plan_interest_controller.dart';

/// IDs internes des fonctionnalités Plan Pro, envoyés à `paid_plan_interest`
/// (agrégation serveur) — mêmes clés que la modal limite
/// (`scenario_limit_reached_modal.dart`). Volontairement NON traduits : ce
/// sont des identifiants techniques stables, jamais affichés à l'utilisateur.
const List<String> _paidPlanFeatureIds = [
  'comparateur',
  'sensibilite_taux',
  'fiscal_lmnp',
  'export_pdf',
];

/// Libellés localisés affichés à l'utilisateur, dans le même ordre que
/// [_paidPlanFeatureIds].
List<String> _paidPlanFeatureLabels(BuildContext context) {
  final l10n = context.l10n;
  return [
    l10n.simulatorPaidPlanFeatureComparator,
    l10n.simulatorPaidPlanFeatureRateSensitivity,
    l10n.simulatorPaidPlanFeatureTaxSimulation,
    l10n.simulatorPaidPlanFeatureExportPdf,
  ];
}

/// Section pied de page `/simulator`, visible uniquement pour le tier FREE
/// (les anonymes voient un CTA « Créer un compte gratuit d'abord » — trop
/// tôt dans leur parcours pour leur vendre un futur plan payant).
class ComingSoonPaidPlanSection extends ConsumerStatefulWidget {
  const ComingSoonPaidPlanSection({super.key});

  @override
  ConsumerState<ComingSoonPaidPlanSection> createState() =>
      _ComingSoonPaidPlanSectionState();
}

class _ComingSoonPaidPlanSectionState
    extends ConsumerState<ComingSoonPaidPlanSection> {
  bool _isSubmitting = false;
  bool _hasNotified = false;
  bool _isSubmittingFunding = false;
  bool _hasFundingInterest = false;

  // NB : le contrôleur passe par AsyncValue.guard — il ne throw JAMAIS,
  // l'échec atterrit dans son state. Il faut donc relire le provider après
  // l'await pour distinguer succès et erreur (un try/catch ici serait du
  // code mort — et afficherait un faux succès sur permission-denied).

  Future<void> _notifyMe() async {
    setState(() => _isSubmitting = true);
    await ref
        .read(paidPlanInterestControllerProvider.notifier)
        .notifyMe(features: _paidPlanFeatureIds);
    if (!mounted) return;

    if (ref.read(paidPlanInterestControllerProvider).hasError) {
      // NE PAS afficher un faux succès et NE PAS locker le bouton :
      // l'utilisateur doit pouvoir retenter. Message d'erreur neutre.
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.simulatorInterestSaveErrorSnackbar),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = false;
      _hasNotified = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.simulatorNotifyMeSuccessSnackbar)),
    );
  }

  Future<void> _expressFundingInterest() async {
    setState(() => _isSubmittingFunding = true);
    await ref
        .read(paidPlanInterestControllerProvider.notifier)
        .expressFundingInterest();
    if (!mounted) return;

    if (ref.read(paidPlanInterestControllerProvider).hasError) {
      // Même politique que _notifyMe : pas de faux succès, retenter possible.
      setState(() => _isSubmittingFunding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.simulatorInterestSaveErrorSnackbar),
        ),
      );
      return;
    }

    setState(() {
      _isSubmittingFunding = false;
      _hasFundingInterest = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.simulatorFundingInterestSuccessSnackbar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Container(
      key: const Key('coming_soon_paid_plan_section'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.simulatorComingSoonTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final label in _paidPlanFeatureLabels(context))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_right_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('coming_soon_notify_button'),
            onPressed: (_isSubmitting || _hasNotified) ? null : _notifyMe,
            child: _isSubmitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _hasNotified
                        ? l10n.simulatorNotifiedButtonLabel
                        : l10n.simulatorNotifyMeButton,
                  ),
          ),

          // ── Soutien / financement ───────────────────────────────────────
          // Signal d'intérêt uniquement (aucun montant, aucun engagement,
          // pas une offre financière) : on recontacte les intéressés.
          const SizedBox(height: 20),
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          const SizedBox(height: 16),
          Text(
            l10n.simulatorFundingSectionTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.simulatorFundingSectionBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('funding_interest_button'),
            onPressed: (_isSubmittingFunding || _hasFundingInterest)
                ? null
                : _expressFundingInterest,
            icon: _isSubmittingFunding
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.volunteer_activism_outlined, size: 18),
            label: Text(
              _hasFundingInterest
                  ? l10n.simulatorFundingThanksButtonLabel
                  : l10n.simulatorFundingInterestButton,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../paid_plan/application/paid_plan_interest_controller.dart';

/// Fonctionnalités à venir du Plan Pro — mêmes clés que la modal limite
/// (`scenario_limit_reached_modal.dart`) pour agréger proprement le signal
/// de demande dans `paid_plan_interest`.
const List<(String key, String label)> _paidPlanFeatures = [
  ('comparateur', 'Comparateur multi-scénarios'),
  ('sensibilite_taux', 'Analyse de sensibilité aux taux'),
  ('fiscal_lmnp', 'Simulation fiscale LMNP/LMP'),
  ('export_pdf', 'Export PDF professionnel'),
];

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

  Future<void> _notifyMe() async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(paidPlanInterestControllerProvider.notifier)
          .notifyMe(features: _paidPlanFeatures.map((f) => f.$1).toList());
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _hasNotified = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous serez prévenu au lancement.')),
      );
    } catch (_) {
      // Firestore permission-denied, network, ou autre : NE PAS afficher un
      // faux succès et NE PAS locker le bouton. L'utilisateur doit pouvoir
      // retenter. Message d'erreur neutre.
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'enregistrer votre intérêt pour le moment. Réessayez.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Prochainement — Plan Pro', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final feature in _paidPlanFeatures)
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
                  Text(feature.$2, style: theme.textTheme.bodyMedium),
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
                        ? 'Vous serez prévenu au lancement'
                        : 'M\'avertir du lancement',
                  ),
          ),
        ],
      ),
    );
  }
}

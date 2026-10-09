import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../application/review_eligibility_provider.dart';
import '../data/review_solicitation_storage.dart';
import '../data/store_review_service.dart';

/// Sollicitation d'avis sur l'Accueil (FEAT-060).
///
/// - App store : si éligible, fenêtre de note native (une fois par montage),
///   jamais précédée d'une question ; la date est enregistrée quand la
///   demande est faite. Rien n'est affiché.
/// - Web : carte « Votre avis compte » → formulaire in-app, ou fermeture.
///   L'une ou l'autre action la masque pour 120 jours.
class AppReviewPrompt extends ConsumerStatefulWidget {
  const AppReviewPrompt({super.key});

  @override
  ConsumerState<AppReviewPrompt> createState() => _AppReviewPromptState();
}

class _AppReviewPromptState extends ConsumerState<AppReviewPrompt> {
  bool _handled = false;

  Future<void> _markSolicited() => ref
      .read(reviewSolicitationStorageProvider)
      .markSolicited(ref.read(reviewClockProvider)());

  Future<void> _requestNativeReview() async {
    final service = ref.read(storeReviewServiceProvider);
    if (!await service.isAvailable()) return;
    await service.requestReview();
    await _markSolicited();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(reviewEligibilityProvider).valueOrNull ?? false;
    if (!eligible || _handled) return const SizedBox.shrink();

    if (isStoreApp) {
      _handled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestNativeReview(),
      );
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('card_review_invite'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.reviewInviteTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('btn_review_invite_close'),
                    tooltip: l10n.reviewInviteCloseTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => _handled = true);
                      _markSolicited();
                    },
                  ),
                ],
              ),
              Text(l10n.reviewInviteBody),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('btn_review_invite_feedback'),
                onPressed: () async {
                  setState(() => _handled = true);
                  await _markSolicited();
                  if (context.mounted) context.push('/profile/feedback');
                },
                child: Text(l10n.reviewInviteButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

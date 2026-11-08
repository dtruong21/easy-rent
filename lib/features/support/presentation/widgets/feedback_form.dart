import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/feedback_controller.dart';
import '../../domain/support_request_state.dart';
import '../../domain/support_submit_error.dart';
import '../support_submit_error_l10n.dart';

/// Plateforme d'origine d'un avis (`support_requests.platform`).
String feedbackPlatform() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

/// Formulaire « Donner mon avis » (FEAT-060) : note 1-5 obligatoire,
/// commentaire facultatif. Aucun renvoi vers les stores selon la note.
class FeedbackForm extends ConsumerStatefulWidget {
  const FeedbackForm({super.key});

  @override
  ConsumerState<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<FeedbackForm> {
  final _commentController = TextEditingController();
  int? _rating;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appVersion = ref
        .read(appInfoProvider)
        .maybeWhen(
          data: (info) => '${info.version}+${info.buildNumber}',
          orElse: () => 'inconnue',
        );
    await ref
        .read(feedbackControllerProvider.notifier)
        .submit(
          rating: _rating,
          comment: _commentController.text,
          appVersion: appVersion,
          appEnv: Env.appEnv,
          platform: feedbackPlatform(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formState = ref.watch(feedbackControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (code) => SupportSubmitError.fromCode(code).message(context),
      orElse: () => null,
    );

    ref.listen<SupportRequestState>(feedbackControllerProvider, (_, next) {
      next.maybeWhen(
        success: () {
          ref.read(feedbackControllerProvider.notifier).reset();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('snackbar_feedback_success'),
              content: Text(l10n.feedbackSuccessSnackbar),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/profile');
          }
        },
        orElse: () {},
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.feedbackRatingLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                key: Key('btn_feedback_star_$i'),
                tooltip: l10n.feedbackStarSemantics(i),
                icon: Icon(
                  _rating != null && i <= _rating!
                      ? Icons.star
                      : Icons.star_border,
                ),
                color: theme.colorScheme.primary,
                // Expose l'étoile choisie aux lecteurs d'écran (la note est
                // le seul champ obligatoire) ; `color` garde le rendu inchangé.
                isSelected: _rating == i,
                onPressed: isSubmitting
                    ? null
                    : () => setState(() => _rating = i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('field_feedback_comment'),
          controller: _commentController,
          enabled: !isSubmitting,
          maxLength: kSupportMessageMaxLength,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: l10n.feedbackCommentLabel,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('btn_feedback_submit'),
          onPressed: (_rating == null || isSubmitting) ? null : _submit,
          child: isSubmitting
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : Text(l10n.feedbackSubmitButton),
        ),
      ],
    );
  }
}

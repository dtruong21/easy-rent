import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info/app_info_provider.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import 'widgets/feedback_form.dart';

/// Page `/profile/feedback` — « Donner mon avis » (FEAT-060).
class FeedbackPage extends ConsumerWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Même réchauffage qu'en SupportPage : appInfoProvider est lu en
    // synchrone (ref.read) au submit.
    ref.watch(appInfoProvider);

    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppAppBar(
        title: l10n.feedbackPageTitle,
        fallbackRoute: '/profile',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.feedbackPageIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                const FeedbackForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/l10n_extensions.dart';

class ProCancelPage extends StatelessWidget {
  const ProCancelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 72,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.proCancelTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.proCancelBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => context.go('/dashboard'),
                      child: Text(l10n.proCancelBackToDashboard),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => context.go('/pro'),
                      child: Text(l10n.proCancelRetry),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

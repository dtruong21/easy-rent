import 'package:flutter/material.dart';

import '../../../profile/presentation/widgets/section_header.dart';
import 'profile_support_form.dart';

/// Section « Support » — formulaire « Nous contacter » (FEAT-025).
///
/// Ne pas présenter ce canal comme une « solution RGPD » dans l'UI (texte
/// volontairement neutre) — voir les notes légales de la story
/// `docs/backlog/025-settings-profile.md`.
class ProfileSupportSection extends StatelessWidget {
  const ProfileSupportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Support'),
        const SizedBox(height: 8),
        Text(
          'Une question, un souci ? Écrivez-nous.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const ProfileSupportForm(),
      ],
    );
  }
}

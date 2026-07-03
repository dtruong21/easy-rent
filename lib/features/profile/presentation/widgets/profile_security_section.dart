import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/auth_session_provider.dart';
import 'profile_change_password_form.dart';
import 'section_header.dart';

/// Section « Sécurité » — changement de mot de passe in-app (FEAT-025).
///
/// **Gating strict** : rien n'est affiché (pas même le header) si
/// [hasPasswordProvider] vaut `false` — comptes Google, Apple ou session
/// anonyme n'ont pas de mot de passe Firebase Auth à changer.
class ProfileSecuritySection extends ConsumerWidget {
  const ProfileSecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPassword = ref.watch(hasPasswordProvider);
    if (!hasPassword) return const SizedBox.shrink();

    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Sécurité'),
        SizedBox(height: 12),
        ProfileChangePasswordForm(),
      ],
    );
  }
}

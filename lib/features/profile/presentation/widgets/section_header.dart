import 'package:flutter/material.dart';

/// Titre de section réutilisable pour la page `/profile`.
///
/// Promu en widget public (FEAT-025) : initialement privé dans
/// `profile_settings_sections.dart`, il est désormais partagé par les
/// sections des features `profile` (Sécurité) et `support` (Nous
/// contacter) sans dupliquer le style.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

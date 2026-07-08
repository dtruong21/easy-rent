import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/l10n_extensions.dart';
import '../breakpoints.dart';
import 'view_mode.dart';
import 'view_mode_provider.dart';

/// Toggle card / tableau pour basculer le mode d'affichage d'une page.
///
/// - Sur mobile (< 600px) : invisible (force le mode carte).
/// - Sur desktop/tablette : [SegmentedButton] Material 3 avec 2 segments.
///
/// Usage :
/// ```dart
/// ViewModeToggle(pageKey: 'leases')
/// ```
class ViewModeToggle extends ConsumerWidget {
  const ViewModeToggle({super.key, required this.pageKey});

  /// Identifiant de la page, utilisé comme clé de persistance.
  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isMobile) {
      return const SizedBox.shrink();
    }

    final currentMode = ref.watch(viewModeProvider(pageKey));
    final l10n = context.l10n;

    return SegmentedButton<ViewMode>(
      segments: [
        ButtonSegment(
          value: ViewMode.card,
          icon: const Icon(Icons.grid_view_outlined),
          label: Text(l10n.commonViewModeCards),
        ),
        ButtonSegment(
          value: ViewMode.table,
          icon: const Icon(Icons.view_list_outlined),
          label: Text(l10n.commonViewModeTable),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          ref.read(viewModeProvider(pageKey).notifier).setMode(selection.first);
        }
      },
      showSelectedIcon: false,
    );
  }
}

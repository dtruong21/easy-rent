import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return SegmentedButton<ViewMode>(
      segments: const [
        ButtonSegment(
          value: ViewMode.card,
          icon: Icon(Icons.grid_view_outlined),
          label: Text('Cartes'),
        ),
        ButtonSegment(
          value: ViewMode.table,
          icon: Icon(Icons.view_list_outlined),
          label: Text('Tableau'),
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

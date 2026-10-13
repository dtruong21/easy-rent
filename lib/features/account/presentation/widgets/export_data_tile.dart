import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/export_data_controller.dart';

/// Tuile « Exporter mes données » du hub Profil (droit à la portabilité,
/// RGPD art. 20).
///
/// Consomme [exportDataControllerProvider] (Task 4) : déclenche
/// [ExportDataController.export] au tap, affiche un indicateur de
/// progression pendant le chargement, puis un `SnackBar` de succès ou
/// d'erreur (message dédié si l'export exige une reconnexion récente).
class ExportDataTile extends ConsumerWidget {
  const ExportDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(exportDataControllerProvider);
    final isLoading = state.status == ExportDataStatus.loading;

    ref.listen<ExportDataState>(exportDataControllerProvider, (_, next) {
      if (!context.mounted) return;
      switch (next.status) {
        case ExportDataStatus.success:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.profileExportDataSuccess),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
        case ExportDataStatus.error:
          final message =
              next.errorKind == ExportDataErrorKind.recentLoginRequired
              ? l10n.profileExportDataRecentLogin
              : l10n.profileExportDataError;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        case ExportDataStatus.idle:
        case ExportDataStatus.loading:
          break;
      }
    });

    return ListTile(
      key: const Key('tile_export_data'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.download_outlined),
      title: Text(l10n.profileExportDataTile),
      subtitle: Text(l10n.profileExportDataSubtitle),
      trailing: isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: isLoading
          ? null
          : () => ref.read(exportDataControllerProvider.notifier).export(),
    );
  }
}

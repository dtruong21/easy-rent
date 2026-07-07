import 'package:flutter/material.dart';

import '../../domain/upload_file_status.dart';
import '../upload_file_error_reason_l10n.dart';

/// Liste les statuts d'upload par fichier pendant et après un batch.
///
/// Affichée dans une Card ou en bas de la drop zone.
/// Chaque fichier montre son nom + icône de statut (en cours, succès, erreur).
class UploadProgressList extends StatelessWidget {
  const UploadProgressList({super.key, required this.files});

  final List<UploadFileStatus> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: files.map((f) => _UploadFileRow(status: f)).toList(),
    );
  }
}

class _UploadFileRow extends StatelessWidget {
  const _UploadFileRow({required this.status});

  final UploadFileStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (status) {
      FilePending(:final filename) => _buildRow(
        context,
        icon: Icons.hourglass_empty_outlined,
        iconColor: theme.colorScheme.onSurfaceVariant,
        filename: filename,
        trailing: null,
      ),
      FileUploading(:final filename, :final progress) => _buildRow(
        context,
        icon: Icons.upload_outlined,
        iconColor: theme.colorScheme.primary,
        filename: filename,
        trailing: SizedBox(
          width: 80,
          child: LinearProgressIndicator(value: progress),
        ),
      ),
      FileSuccess(:final filename) => _buildRow(
        context,
        icon: Icons.check_circle_outline,
        iconColor: theme.colorScheme.primary,
        filename: filename,
        trailing: null,
      ),
      FileError(:final filename, :final reason) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(
            context,
            icon: Icons.error_outline,
            iconColor: theme.colorScheme.error,
            filename: filename,
            trailing: null,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: Text(
              reason.message(context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    };
  }

  Widget _buildRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String filename,
    required Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filename,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

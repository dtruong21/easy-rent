import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../application/documents_quota_provider.dart';
import '../../application/lease_documents_provider.dart';
import 'documents_list.dart';
import 'upload_documents_drop_zone.dart';

final _log = Logger('DocumentsSection');

/// Section "Documents" intégrée dans [LeaseDetailPage].
///
/// Affiche le quota warning si applicable, la drop zone d'upload et la liste.
class DocumentsSection extends ConsumerWidget {
  const DocumentsSection({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDocuments = ref.watch(leaseDocumentsProvider(leaseId));
    final asyncQuota = ref.watch(documentsQuotaProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre de section
            Text('Documents', style: theme.textTheme.titleMedium),

            // Banner quota si dépassement
            asyncQuota.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
              data: (quota) {
                if (!quota.isOverSoftLimit) return const SizedBox.shrink();
                return _QuotaWarningBanner();
              },
            ),

            const SizedBox(height: 12),

            // Zone d'upload toujours visible
            UploadDocumentsDropZone(leaseId: leaseId),

            const SizedBox(height: 12),

            // Liste des documents ou état de chargement
            asyncDocuments.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) {
                _log.warning('Erreur chargement documents', e);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Erreur lors du chargement des documents.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                );
              },
              data: (documents) =>
                  DocumentsList(documents: documents, leaseId: leaseId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner non-dismissable affiché quand le quota dépasse 100 Mo.
class _QuotaWarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vous avez dépassé 100 Mo d\'espace de stockage. '
              'Pensez à supprimer les documents obsolètes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

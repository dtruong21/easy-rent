import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/french_date.dart';
import '../../../core/widgets/archive_confirm_dialog.dart';
import '../application/properties_list_provider.dart';
import '../application/property_detail_provider.dart';
import '../data/property_repository.dart';
import '../domain/property.dart';

final _log = Logger('PropertyDetailPage');

/// Fiche lecture d'un bien immobilier.
///
/// Route : `/properties/:id`
///
/// Affiche toutes les informations + boutons "Modifier" et "Archiver".
/// Section "Baux actifs" : stub V1 (disponible après FEAT-005).
///
/// Critères Gherkin :
/// - Cross-user : si RLS retourne 0 ligne → "Bien introuvable".
/// - Archivage via RPC `soft_delete_property` (jamais UPDATE direct).
/// - Dialog standard ou renforcé selon présence de bail actif.
class PropertyDetailPage extends ConsumerWidget {
  const PropertyDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperty = ref.watch(propertyDetailProvider(id));

    return asyncProperty.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _NotFoundPage(id: id),
      data: (property) => _PropertyDetailContent(property: property),
    );
  }
}

/// Vue principale quand le bien est chargé.
class _PropertyDetailContent extends ConsumerWidget {
  const _PropertyDetailContent({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(property.name),
        leading: BackButton(onPressed: () => context.go('/properties')),
        actions: [
          IconButton(
            key: const Key('btn_edit_property'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: () => context.push('/properties/${property.id}/edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoCard(property: property),
            const SizedBox(height: 24),

            // Section baux — stub V1
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Baux actifs',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Disponible après FEAT-005',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Bouton Archiver
            OutlinedButton.icon(
              key: const Key('btn_archive_property'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archiver ce bien'),
              onPressed: () => _confirmArchive(context, ref, property),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    Property property,
  ) async {
    // Compter les baux actifs avant d'afficher le dialog.
    int activeLeaseCount = 0;
    try {
      activeLeaseCount = await ref
          .read(propertyRepositoryProvider)
          .countActiveLeases(property.id);
    } catch (e, st) {
      _log.warning('countActiveLeases failed', e, st);
      // En cas d'erreur, on affiche le dialog standard (non bloquant).
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: 'Archiver ce bien ?',
        entityLabel: property.name,
        standardMessage:
            'Voulez-vous archiver "${property.name}" ? '
            "Le bien n'apparaîtra plus dans votre liste. "
            'Les baux liés seront conservés.',
        activeLeaseMessage:
            'Ce bien a un bail actif. Êtes-vous sûr de vouloir archiver '
            '"${property.name}" ? Les baux actifs liés seront conservés '
            "mais le bien n'apparaîtra plus dans votre liste.",
        hasActiveLease: activeLeaseCount > 0,
        onConfirm: () => _archive(context, ref, property),
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Property property,
  ) async {
    try {
      await ref.read(propertyRepositoryProvider).archive(property.id);
      // Invalider la liste ET la fiche.
      ref.invalidate(propertiesListProvider);
      ref.invalidate(propertyDetailProvider(property.id));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bien archivé'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
      context.go('/properties');
    } catch (e, st) {
      _log.severe('archive failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Impossible d'archiver ce bien. Veuillez réessayer.",
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }
}

/// Carte d'information du bien (lecture seule).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              icon: Icons.label_outline,
              label: 'Nom',
              value: property.name,
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Adresse',
              value: property.address,
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.home_outlined,
              label: 'Type',
              value: property.type.labelFr,
            ),
            if (property.surfaceM2 != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.square_foot,
                label: 'Surface',
                value:
                    '${property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2)} m²',
              ),
            ],
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Ajouté le',
              value: FrenchDate.format(property.createdAt),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.update,
              label: 'Modifié le',
              value: FrenchDate.format(property.updatedAt),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// Page "Bien introuvable" — affichée quand la RLS retourne 0 ligne.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche bien'),
        leading: BackButton(onPressed: () => context.go('/properties')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 80,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Bien introuvable',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ce bien a peut-être été archivé ou ne vous appartient pas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/properties'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Retour à la liste'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

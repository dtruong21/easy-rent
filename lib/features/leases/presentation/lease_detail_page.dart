import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/money_format.dart';
import '../../../core/widgets/archive_confirm_dialog.dart';
import '../../../core/widgets/lease_status_badge.dart';
import '../application/lease_detail_provider.dart';
import '../application/lease_form_controller.dart';
import '../application/leases_list_provider.dart';
import '../data/lease_repository.dart';
import '../domain/lease.dart';
import '../domain/lease_form_state.dart';
import 'widgets/close_lease_dialog.dart';

final _log = Logger('LeaseDetailPage');

/// Fiche lecture d'un bail.
///
/// Route : `/leases/:id`
///
/// Affiche toutes les informations + boutons "Modifier", "Clôturer" (si actif)
/// et "Archiver".
/// Section paiements : placeholder "Disponible après FEAT-006".
class LeaseDetailPage extends ConsumerWidget {
  const LeaseDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLease = ref.watch(leaseDetailProvider(id));

    return asyncLease.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _NotFoundPage(id: id),
      data: (lease) => _LeaseDetailContent(lease: lease),
    );
  }
}

/// Vue principale quand le bail est chargé.
class _LeaseDetailContent extends ConsumerWidget {
  const _LeaseDetailContent({required this.lease});

  final Lease lease;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Écouter l'état du contrôleur de clôture pour les feedbacks.
    ref.listen<LeaseFormState>(leaseFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Bail clôturé'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        },
        error: (msg) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bail'),
        leading: BackButton(onPressed: () => context.go('/leases')),
        actions: [
          IconButton(
            key: const Key('btn_edit_lease'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: () => context.push('/leases/${lease.id}/edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(lease: lease),
            const SizedBox(height: 16),
            _InfoCard(lease: lease),
            const SizedBox(height: 16),
            _PaymentsPlaceholder(),
            const SizedBox(height: 32),

            // Bouton Clôturer (uniquement si bail actif)
            if (lease.isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  key: const Key('btn_close_lease'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  icon: const Icon(Icons.do_not_disturb_outlined),
                  label: const Text('Clôturer ce bail'),
                  onPressed: () => _showCloseDialog(context, ref),
                ),
              ),

            // Bouton Archiver
            OutlinedButton.icon(
              key: const Key('btn_archive_lease'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archiver ce bail'),
              onPressed: () => _confirmArchive(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => CloseLeaseDialog(
        onClose: (effectiveEndDate) => ref
            .read(leaseFormControllerProvider.notifier)
            .close(leaseId: lease.id, effectiveEndDate: effectiveEndDate),
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: 'Archiver ce bail ?',
        entityLabel: 'Ce bail',
        standardMessage:
            'Voulez-vous archiver ce bail ? '
            "Il n'apparaîtra plus dans votre liste.",
        activeLeaseMessage:
            'Ce bail est encore actif. Êtes-vous sûr de vouloir l\'archiver ? '
            "Il n'apparaîtra plus dans votre liste.",
        hasActiveLease: lease.isActive,
        onConfirm: () => _archive(context, ref),
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(leaseRepositoryProvider).archive(lease.id);
      ref.invalidate(leasesListProvider);
      ref.invalidate(leaseDetailProvider(lease.id));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bail archivé'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
      context.go('/leases');
    } catch (e, st) {
      _log.severe('archive lease failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Impossible d'archiver ce bail. Veuillez réessayer.",
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }
}

/// Card statut du bail.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.lease});

  final Lease lease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('Statut', style: theme.textTheme.titleMedium),
            const Spacer(),
            LeaseStatusBadge(status: lease.status.sqlValue),
          ],
        ),
      ),
    );
  }
}

/// Card d'informations du bail (lecture seule).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.lease});

  final Lease lease;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bien lié — lien cliquable
            _LinkRow(
              icon: Icons.home_outlined,
              label: 'Bien',
              onTap: () => context.go('/properties/${lease.propertyId}'),
            ),
            const Divider(height: 24),

            // Locataire lié — lien cliquable
            _LinkRow(
              icon: Icons.person_outline,
              label: 'Locataire',
              onTap: () => context.go('/tenants/${lease.tenantId}'),
            ),
            const Divider(height: 24),

            _InfoRow(
              icon: Icons.euro_outlined,
              label: 'Loyer HC',
              value: MoneyFormat.formatEurosFromCents(lease.rentAmountCents),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.add_circle_outline,
              label: 'Charges',
              value: MoneyFormat.formatEurosFromCents(lease.chargesAmountCents),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.euro,
              label: 'Loyer CC',
              value: MoneyFormat.formatEurosFromCents(lease.totalAmountCents),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Début',
              value: _formatDate(lease.startDate),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.event_outlined,
              label: 'Fin',
              value: lease.endDate != null
                  ? _formatDate(lease.endDate!)
                  : '(CDI)',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

/// Ligne avec un lien cliquable (pour bien et locataire).
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
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
                Text(
                  'Voir la fiche',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.primary),
        ],
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

/// Section paiements — placeholder FEAT-006.
class _PaymentsPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paiements', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Suivi des paiements disponible après FEAT-006.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page "Bail introuvable" — affichée quand la RLS retourne 0 ligne.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche bail'),
        leading: BackButton(onPressed: () => context.go('/leases')),
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
                'Bail introuvable',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ce bail a peut-être été archivé ou ne vous appartient pas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/leases'),
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

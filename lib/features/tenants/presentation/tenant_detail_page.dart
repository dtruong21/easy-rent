import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/french_date.dart';
import '../../../core/widgets/archive_confirm_dialog.dart';
import '../application/tenant_detail_provider.dart';
import '../application/tenants_list_provider.dart';
import '../data/tenant_repository.dart';
import '../domain/tenant.dart';
import 'widgets/tenant_lease_summary.dart';

final _log = Logger('TenantDetailPage');

/// Fiche lecture d'un locataire.
///
/// Route : `/tenants/:id`
///
/// Affiche toutes les informations + boutons "Modifier" et "Archiver".
/// Section "Baux liés" : query directe `leases` via `TenantRepository.listLeasesForTenant`.
///
/// Critères Gherkin :
/// - Cross-user : si RLS retourne 0 ligne → "Locataire introuvable".
/// - Archivage via RPC `soft_delete_tenant` (jamais UPDATE direct).
/// - Dialog standard ou renforcé selon présence de bail actif.
class TenantDetailPage extends ConsumerWidget {
  const TenantDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTenant = ref.watch(tenantDetailProvider(id));

    return asyncTenant.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _NotFoundPage(id: id),
      data: (tenant) => _TenantDetailContent(tenant: tenant),
    );
  }
}

/// Vue principale quand le locataire est chargé.
class _TenantDetailContent extends ConsumerWidget {
  const _TenantDetailContent({required this.tenant});

  final Tenant tenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppAppBar(
        title: '${tenant.firstName} ${tenant.lastName}',
        fallbackRoute: '/tenants',
        actions: [
          IconButton(
            key: const Key('btn_edit_tenant'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: () => context.push('/tenants/${tenant.id}/edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoCard(tenant: tenant),
            const SizedBox(height: 24),

            // Section baux liés
            _LeasesSection(tenantId: tenant.id),
            const SizedBox(height: 32),

            // Bouton Archiver
            OutlinedButton.icon(
              key: const Key('btn_archive_tenant'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archiver ce locataire'),
              onPressed: () => _confirmArchive(context, ref, tenant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    Tenant tenant,
  ) async {
    // Compter les baux actifs avant d'afficher le dialog.
    int activeLeaseCount = 0;
    try {
      activeLeaseCount = await ref
          .read(tenantRepositoryProvider)
          .countActiveLeases(tenant.id);
    } catch (e, st) {
      _log.warning('countActiveLeases failed', e, st);
      // En cas d'erreur, on affiche le dialog standard (non bloquant).
    }

    if (!context.mounted) return;

    final displayName = '${tenant.firstName} ${tenant.lastName}';

    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: 'Archiver ce locataire ?',
        entityLabel: displayName,
        standardMessage:
            'Voulez-vous archiver "$displayName" ? '
            "Le locataire n'apparaîtra plus dans votre liste. "
            'Les baux liés seront conservés.',
        activeLeaseMessage:
            'Ce locataire a un bail actif. Êtes-vous sûr de vouloir archiver '
            '"$displayName" ? Les baux actifs liés seront conservés '
            "mais le locataire n'apparaîtra plus dans votre liste.",
        hasActiveLease: activeLeaseCount > 0,
        onConfirm: () => _archive(context, ref, tenant),
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Tenant tenant,
  ) async {
    try {
      await ref.read(tenantRepositoryProvider).archive(tenant.id);
      // Invalider la liste ET la fiche.
      ref.invalidate(tenantsListProvider);
      ref.invalidate(tenantDetailProvider(tenant.id));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Locataire archivé'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
      context.go('/tenants');
    } catch (e, st) {
      _log.severe('archive failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Impossible d'archiver ce locataire. Veuillez réessayer.",
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }
}

/// Carte d'information du locataire (lecture seule).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.tenant});

  final Tenant tenant;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Prénom',
              value: tenant.firstName,
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Nom',
              value: tenant.lastName,
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: tenant.email,
            ),
            if (tenant.phone != null && tenant.phone!.isNotEmpty) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Téléphone',
                value: tenant.phone!,
              ),
            ],
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Ajouté le',
              value: FrenchDate.format(tenant.createdAt),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.update,
              label: 'Modifié le',
              value: FrenchDate.format(tenant.updatedAt),
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

/// Section baux liés — charge depuis le repository et affiche [TenantLeaseSummary].
class _LeasesSection extends ConsumerStatefulWidget {
  const _LeasesSection({required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<_LeasesSection> createState() => _LeasesSectionState();
}

class _LeasesSectionState extends ConsumerState<_LeasesSection> {
  List<Map<String, dynamic>>? _leases;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLeases();
  }

  Future<void> _fetchLeases() async {
    try {
      final leases = await ref
          .read(tenantRepositoryProvider)
          .listLeasesForTenant(widget.tenantId);
      if (mounted) {
        setState(() {
          _leases = leases;
          _loading = false;
        });
      }
    } catch (e, st) {
      _log.warning('listLeasesForTenant failed', e, st);
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger les baux.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Baux liés', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              TenantLeaseSummary(leases: _leases ?? []),
          ],
        ),
      ),
    );
  }
}

/// Page "Locataire introuvable" — affichée quand la RLS retourne 0 ligne.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Fiche locataire', fallbackRoute: '/tenants'),
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
                'Locataire introuvable',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ce locataire a peut-être été archivé ou ne vous appartient pas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/tenants'),
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

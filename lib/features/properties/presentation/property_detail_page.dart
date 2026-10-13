import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/theme/property_color.dart';
import '../../../core/utils/french_date.dart';
import '../../../core/widgets/archive_confirm_dialog.dart';
import '../../expenses/presentation/widgets/expenses_history_section.dart';
import '../../leases/data/lease_repository.dart';
import '../application/properties_list_provider.dart';
import '../application/property_detail_provider.dart';
import '../data/property_repository.dart';
import '../domain/property.dart';
import 'widgets/heating_type_l10n.dart';
import 'widgets/property_color_dot.dart';
import 'widgets/property_color_l10n.dart';
import 'widgets/property_lease_summary.dart';
import 'widgets/property_profitability_card.dart';
import 'widgets/property_type_l10n.dart';

final _log = Logger('PropertyDetailPage');

/// Fiche lecture d'un bien immobilier.
///
/// Route : `/properties/:id`
///
/// Affiche toutes les informations + boutons "Modifier" et "Archiver".
/// Section "Baux actifs" : query directe `leases` via
/// `LeaseRepository.listActiveLeasesForProperty` (FEAT-005). Ne montre que
/// les baux `status == active` — les baux terminés/archivés du bien restent
/// consultables depuis la fiche bail / la liste des baux, pas dupliqués ici.
///
/// Critères Gherkin :
/// - Cross-user : si les Firestore Rules ne renvoient aucun document → "Bien introuvable".
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppAppBar(
        title: property.name,
        fallbackRoute: '/properties',
        actions: [
          IconButton(
            key: const Key('btn_edit_property'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.commonEdit,
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

            // Section rentabilité (FEAT-017)
            PropertyProfitabilityCard(propertyId: property.id),
            const SizedBox(height: 24),

            // Section dépenses (FEAT-041a)
            ExpensesHistorySection(propertyId: property.id),
            const SizedBox(height: 24),

            // Section baux actifs
            _LeasesSection(propertyId: property.id),
            const SizedBox(height: 32),

            // Bouton Archiver
            OutlinedButton.icon(
              key: const Key('btn_archive_property'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: Text(l10n.propertiesDetailArchiveButton),
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
    final l10n = context.l10n;

    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: l10n.propertiesArchiveDialogTitle,
        entityLabel: property.name,
        standardMessage: l10n.propertiesArchiveDialogStandardMessage(
          property.name,
        ),
        activeLeaseMessage: l10n.propertiesArchiveDialogActiveLeaseMessage(
          property.name,
        ),
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
          content: Text(context.l10n.propertiesArchiveSuccessSnackbar),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
      context.go('/properties');
    } catch (e, st) {
      _log.severe('archive failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.propertiesArchiveErrorSnackbar),
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
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              icon: Icons.label_outline,
              label: l10n.propertiesFieldName,
              value: property.name,
            ),
            const Divider(height: 24),
            _ColorInfoRow(property: property),

            // --- Localisation ---
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: l10n.propertiesFieldAddress,
              value: property.address,
            ),
            if (property.postalCode != null || property.city != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.place_outlined,
                label: l10n.propertiesFieldCity,
                value: [
                  if (property.postalCode != null) property.postalCode!,
                  if (property.city != null) property.city!,
                ].join(' '),
              ),
            ],

            // --- Caractéristiques ---
            const Divider(height: 24),
            Text(
              l10n.propertiesSectionCharacteristics,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.home_outlined,
              label: l10n.propertiesFieldType,
              value: property.type.label(context),
            ),
            if (property.surfaceM2 != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.square_foot,
                label: l10n.propertiesFieldSurface,
                value: l10n.propertiesSurfaceValue(
                  property.surfaceM2!.toStringAsFixed(
                    property.surfaceM2! % 1 == 0 ? 0 : 2,
                  ),
                ),
              ),
            ],
            if (property.rooms != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.grid_view_outlined,
                label: l10n.propertiesFieldRooms,
                value: '${property.rooms}',
              ),
            ],
            if (property.bedrooms != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.bed_outlined,
                label: l10n.propertiesFieldBedrooms,
                value: '${property.bedrooms}',
              ),
            ],
            if (property.floor != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.stairs_outlined,
                label: l10n.propertiesFieldFloor,
                value: '${property.floor}',
              ),
            ],
            if (property.hasElevator) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.elevator_outlined,
                label: l10n.propertiesFieldElevator,
                value: l10n.commonYes,
              ),
            ],
            if (property.furnished) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.chair_outlined,
                label: l10n.propertiesFieldFurnished,
                value: l10n.commonYes,
              ),
            ],
            if (property.heatingType != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.thermostat_outlined,
                label: l10n.propertiesFieldHeating,
                value: property.heatingType!.label(context),
              ),
            ],
            if (property.constructionYear != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.construction_outlined,
                label: l10n.propertiesFieldConstructionYear,
                value: '${property.constructionYear}',
              ),
            ],

            // --- Performance énergétique (DPE / GES) ---
            if (property.dpeLetter != null ||
                property.dpeValueKwhM2Year != null ||
                property.gesLetter != null) ...[
              const Divider(height: 24),
              Text(
                l10n.propertiesSectionEnergyPerformance,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (property.dpeLetter != null) ...[
                _InfoRow(
                  icon: Icons.energy_savings_leaf_outlined,
                  label: l10n.propertiesFieldDpeClass,
                  value: property.dpeLetter!,
                ),
              ],
              if (property.dpeValueKwhM2Year != null) ...[
                const Divider(height: 24),
                _InfoRow(
                  icon: Icons.bolt_outlined,
                  label: l10n.propertiesFieldDpeConsumption,
                  value: l10n.propertiesDpeConsumptionValue(
                    property.dpeValueKwhM2Year!,
                  ),
                ),
              ],
              if (property.gesLetter != null) ...[
                const Divider(height: 24),
                _InfoRow(
                  icon: Icons.cloud_outlined,
                  label: l10n.propertiesFieldGesClass,
                  value: property.gesLetter!,
                ),
              ],
            ],

            // --- Dates ---
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: l10n.propertiesFieldCreatedAt,
              value: FrenchDate.format(property.createdAt),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.update,
              label: l10n.propertiesFieldUpdatedAt,
              value: FrenchDate.format(property.updatedAt),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne "Couleur" — pastille + nom localisé de la teinte résolue.
///
/// Modifiable uniquement depuis le formulaire d'édition (cf.
/// `PropertyColorPicker`) — cette ligne est en lecture seule ici.
class _ColorInfoRow extends StatelessWidget {
  const _ColorInfoRow({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colorKey = PropertyColorKey.resolve(
      entityId: property.id,
      stored: property.colorKey,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: PropertyColorDot(colorKey: colorKey, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.propertiesFieldColor,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(colorKey.label(context), style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
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

/// Section baux actifs — charge depuis le repository et affiche [PropertyLeaseSummary].
class _LeasesSection extends ConsumerStatefulWidget {
  const _LeasesSection({required this.propertyId});

  final String propertyId;

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
          .read(leaseRepositoryProvider)
          .listActiveLeasesForProperty(widget.propertyId);
      if (mounted) {
        setState(() {
          _leases = leases;
          _loading = false;
        });
      }
    } catch (e, st) {
      _log.warning('listActiveLeasesForProperty failed', e, st);
      if (mounted) {
        setState(() {
          _error = context.l10n.tenantsErrorLoadLeases;
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
            Text(
              context.l10n.propertiesDetailActiveLeasesTitle,
              style: theme.textTheme.titleMedium,
            ),
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
              PropertyLeaseSummary(leases: _leases ?? []),
          ],
        ),
      ),
    );
  }
}

/// Page "Bien introuvable" — affichée quand les Firestore Rules ne renvoient aucun document.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppAppBar(
        title: l10n.propertiesDetailAppBarTitle,
        fallbackRoute: '/properties',
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
                l10n.propertiesNotFoundTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.propertiesNotFoundMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/properties'),
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.propertiesBackToListButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

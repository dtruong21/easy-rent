import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../domain/property_list_item.dart';
import 'property_status_mapper.dart';

/// Colonnes triables du tableau biens.
enum _PropertyTableSort { name, type, surface, tenant, amount }

/// Vue en tableau (DataTable M3) pour la liste des biens immobiliers.
///
/// 7 colonnes : Bien, Type, Surface, Statut, Locataire, Loyer CC, Actions.
/// Tri client-side sur 5 colonnes.
/// Lignes cliquables via [DataRow.onSelectChanged].
/// Container : fond [surfaceContainerLow], bordure [outlineVariant], radius md.
///
/// Affiche 6 lignes squelettes pendant le chargement via [PropertiesTableView.loading].
class PropertiesTableView extends StatefulWidget {
  const PropertiesTableView({super.key, required this.properties});

  final List<PropertyListItem> properties;

  /// Vue squelette de chargement.
  static Widget loading() => const _PropertiesTableViewLoading();

  @override
  State<PropertiesTableView> createState() => _PropertiesTableViewState();
}

class _PropertiesTableViewState extends State<PropertiesTableView> {
  _PropertyTableSort _sortColumn = _PropertyTableSort.name;
  bool _sortAscending = true;

  List<PropertyListItem> get _sorted {
    final list = List<PropertyListItem>.from(widget.properties);
    list.sort((a, b) {
      final cmp = switch (_sortColumn) {
        _PropertyTableSort.name => a.property.name.compareTo(b.property.name),
        _PropertyTableSort.type => a.property.type.labelFr.compareTo(
          b.property.type.labelFr,
        ),
        _PropertyTableSort.surface => (a.property.surfaceM2 ?? 0).compareTo(
          b.property.surfaceM2 ?? 0,
        ),
        _PropertyTableSort.tenant => (a.currentTenantName ?? '').compareTo(
          b.currentTenantName ?? '',
        ),
        _PropertyTableSort.amount =>
          (a.activeLeaseId != null ? 1 : 0).compareTo(
            b.activeLeaseId != null ? 1 : 0,
          ),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumn = _PropertyTableSort.values[columnIndex];
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = _sorted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: _PropertyTableSort.values.indexOf(_sortColumn),
            sortAscending: _sortAscending,
            columns: [
              DataColumn(label: const Text('Bien'), onSort: _onSort),
              DataColumn(label: const Text('Type'), onSort: _onSort),
              DataColumn(
                label: const Text('Surface'),
                numeric: true,
                onSort: _onSort,
              ),
              const DataColumn(label: Text('Statut')),
              DataColumn(label: const Text('Locataire'), onSort: _onSort),
              DataColumn(
                label: const Text('Loyer CC'),
                numeric: true,
                onSort: _onSort,
              ),
              const DataColumn(label: Text('Actions')),
            ],
            rows: items.map((item) => _buildRow(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, PropertyListItem item) {
    final property = item.property;
    final pillData = propertyOccupancyPill(item);

    final surfaceText = property.surfaceM2 != null
        ? '${property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2)} m²'
        : '—';

    return DataRow(
      onSelectChanged: (_) => context.push('/properties/${property.id}'),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  property.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  property.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 110,
            child: Text(
              property.type.labelFr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(surfaceText)),
        DataCell(
          StatusPill(
            tone: pillData.tone,
            label: pillData.label,
            icon: pillData.icon,
            size: StatusPillSize.sm,
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 160),
            child: Text(
              item.currentTenantName ?? 'Aucun locataire',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(item.currentRentLabel ?? '—')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('table_edit_${property.id}'),
                onPressed: () =>
                    context.push('/properties/${property.id}/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Modifier',
                visualDensity: VisualDensity.compact,
              ),
              if (item.activeLeaseId != null)
                IconButton(
                  key: Key('table_lease_${property.id}'),
                  onPressed: () =>
                      context.push('/leases/${item.activeLeaseId}'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  tooltip: 'Voir le bail',
                  visualDensity: VisualDensity.compact,
                )
              else
                IconButton(
                  key: Key('table_new_lease_${property.id}'),
                  onPressed: () =>
                      context.push('/leases/new?propertyId=${property.id}'),
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Créer un bail',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Squelette de chargement
// ---------------------------------------------------------------------------

class _PropertiesTableViewLoading extends StatelessWidget {
  const _PropertiesTableViewLoading();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TableSkeletonHeader(),
              const SizedBox(height: 8),
              ...List.generate(
                6,
                (_) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _TableSkeletonRow(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableSkeletonHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant.withAlpha(153);

    return Row(
      children: List.generate(
        7,
        (i) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            width: 100,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableSkeletonRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant.withAlpha(153);

    return Row(
      children: List.generate(
        7,
        (i) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            width: 120,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

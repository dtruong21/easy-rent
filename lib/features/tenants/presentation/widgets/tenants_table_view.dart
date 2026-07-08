import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/tenant_list_item.dart';
import 'tenant_status_mapper.dart';

/// Colonnes triables du tableau locataires.
enum _TenantTableSort { name, email, property, amount }

/// Vue en tableau (DataTable M3) pour la liste des locataires.
///
/// 7 colonnes : Nom, Email, Téléphone, Statut, Bien occupé, Loyer CC, Actions.
/// Tri client-side sur 4 colonnes.
/// Lignes cliquables via [DataRow.onSelectChanged].
/// Container : fond [surfaceContainerLow], bordure [outlineVariant], radius md.
///
/// Affiche 6 lignes squelettes pendant le chargement via [TenantsTableView.loading].
class TenantsTableView extends StatefulWidget {
  const TenantsTableView({super.key, required this.tenants});

  final List<TenantListItem> tenants;

  /// Vue squelette de chargement.
  static Widget loading() => const _TenantsTableViewLoading();

  @override
  State<TenantsTableView> createState() => _TenantsTableViewState();
}

class _TenantsTableViewState extends State<TenantsTableView> {
  _TenantTableSort _sortColumn = _TenantTableSort.name;
  bool _sortAscending = true;

  List<TenantListItem> get _sorted {
    final list = List<TenantListItem>.from(widget.tenants);
    list.sort((a, b) {
      final cmp = switch (_sortColumn) {
        _TenantTableSort.name =>
          '${a.tenant.lastName} ${a.tenant.firstName}'.compareTo(
            '${b.tenant.lastName} ${b.tenant.firstName}',
          ),
        _TenantTableSort.email => a.tenant.email.compareTo(b.tenant.email),
        _TenantTableSort.property => (a.currentPropertyName ?? '').compareTo(
          b.currentPropertyName ?? '',
        ),
        _TenantTableSort.amount => (a.activeLeaseRentCents ?? 0).compareTo(
          b.activeLeaseRentCents ?? 0,
        ),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumn = _TenantTableSort.values[columnIndex];
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
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
            sortColumnIndex: _TenantTableSort.values.indexOf(_sortColumn),
            sortAscending: _sortAscending,
            columns: [
              DataColumn(
                label: Text(l10n.tenantsTableColumnName),
                onSort: _onSort,
              ),
              DataColumn(
                label: Text(l10n.tenantsTableColumnEmail),
                onSort: _onSort,
              ),
              DataColumn(label: Text(l10n.tenantsTableColumnPhone)),
              DataColumn(label: Text(l10n.tenantsTableColumnStatus)),
              DataColumn(
                label: Text(l10n.tenantsTableColumnProperty),
                onSort: _onSort,
              ),
              DataColumn(
                label: Text(l10n.tenantsTableColumnRent),
                numeric: true,
                onSort: _onSort,
              ),
              DataColumn(label: Text(l10n.tenantsTableColumnActions)),
            ],
            rows: items.map((item) => _buildRow(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, TenantListItem item) {
    final l10n = context.l10n;
    final tenant = item.tenant;
    final pillData = tenantOccupancyPill(context, item);

    final rentLabel = item.activeLeaseRentCents != null
        ? MoneyFormat.formatEurosFromCents(item.activeLeaseRentCents!)
        : '—';

    return DataRow(
      onSelectChanged: (_) => context.push('/tenants/${tenant.id}'),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${tenant.firstName} ${tenant.lastName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
            child: Text(
              tenant.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 110,
            child: Text(
              tenant.phone ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
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
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
            child: Text(
              item.currentPropertyName ?? l10n.tenantsNoPropertyOccupied,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(rentLabel)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('table_edit_${tenant.id}'),
                onPressed: () => context.push('/tenants/${tenant.id}/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: l10n.commonEdit,
                visualDensity: VisualDensity.compact,
              ),
              if (item.activeLeaseId != null)
                IconButton(
                  key: Key('table_lease_${tenant.id}'),
                  onPressed: () =>
                      context.push('/leases/${item.activeLeaseId}'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  tooltip: l10n.tenantsViewLeaseButton,
                  visualDensity: VisualDensity.compact,
                )
              else
                IconButton(
                  key: Key('table_new_lease_${tenant.id}'),
                  onPressed: () =>
                      context.push('/leases/new?tenantId=${tenant.id}'),
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: l10n.tenantsCreateLeaseButton,
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

class _TenantsTableViewLoading extends StatelessWidget {
  const _TenantsTableViewLoading();

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

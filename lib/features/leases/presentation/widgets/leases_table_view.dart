import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/lease.dart';
import '../../domain/lease_list_item.dart';
import 'lease_status_mapper.dart';

/// Colonnes triables du tableau baux.
enum _LeaseTableSort { property, tenant, startDate, amount }

/// Vue en tableau (DataTable M3) pour la liste des baux.
///
/// Tri client-side sur 4 colonnes.
/// Lignes cliquables via [DataRow.onSelectChanged].
/// Container : fond [surfaceContainerLow], bordure [outlineVariant], radius md.
///
/// Affiche 6 lignes squelettes pendant le chargement via [LeasesTableView.loading].
class LeasesTableView extends StatefulWidget {
  const LeasesTableView({super.key, required this.leases});

  final List<LeaseListItem> leases;

  /// Vue squelette de chargement.
  static Widget loading() => const _LeasesTableViewLoading();

  @override
  State<LeasesTableView> createState() => _LeasesTableViewState();
}

class _LeasesTableViewState extends State<LeasesTableView> {
  _LeaseTableSort _sortColumn = _LeaseTableSort.property;
  bool _sortAscending = true;

  List<LeaseListItem> get _sorted {
    final list = List<LeaseListItem>.from(widget.leases);
    list.sort((a, b) {
      final cmp = switch (_sortColumn) {
        _LeaseTableSort.property => a.propertyName.compareTo(b.propertyName),
        _LeaseTableSort.tenant => a.tenantDisplayName.compareTo(
          b.tenantDisplayName,
        ),
        _LeaseTableSort.startDate => a.lease.startDate.compareTo(
          b.lease.startDate,
        ),
        _LeaseTableSort.amount => a.lease.totalAmountCents.compareTo(
          b.lease.totalAmountCents,
        ),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumn = _LeaseTableSort.values[columnIndex];
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
            sortColumnIndex: _LeaseTableSort.values.indexOf(_sortColumn),
            sortAscending: _sortAscending,
            columns: [
              DataColumn(label: const Text('Bien'), onSort: _onSort),
              DataColumn(label: const Text('Locataire'), onSort: _onSort),
              const DataColumn(label: Text('Période')),
              DataColumn(
                label: const Text('Loyer CC'),
                numeric: true,
                onSort: _onSort,
              ),
              const DataColumn(label: Text('Statut')),
              const DataColumn(label: Text('Actions')),
            ],
            rows: items.map((item) => _buildRow(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, LeaseListItem item) {
    final lease = item.lease;
    final pillData = leaseStatusPill(lease, isLate: item.isLate);

    return DataRow(
      onSelectChanged: (_) => context.push('/leases/${lease.id}'),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
            child: Text(
              item.propertyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
            child: Text(
              item.tenantDisplayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 200,
            child: Text(
              _formatPeriod(lease.startDate, lease.endDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(
            '${MoneyFormat.formatEurosFromCents(lease.totalAmountCents)} CC',
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('table_receipts_${lease.id}'),
                onPressed: () => context.push('/leases/${lease.id}/receipts'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                tooltip: 'Quittances',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: Key('table_payment_${lease.id}'),
                onPressed: () =>
                    context.push('/leases/${lease.id}/payments/new'),
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Ajouter paiement',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPeriod(DateTime startDate, DateTime? endDate) {
    final start = FrenchDate.format(startDate);
    if (endDate == null) {
      return '$start → CDI';
    }
    return '$start → ${FrenchDate.format(endDate)}';
  }
}

// ---------------------------------------------------------------------------
// Squelette de chargement
// ---------------------------------------------------------------------------

class _LeasesTableViewLoading extends StatelessWidget {
  const _LeasesTableViewLoading();

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
              // En-tête squelette
              _TableSkeletonHeader(),
              const SizedBox(height: 8),
              // 6 lignes squelettes
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
        6,
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
        6,
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

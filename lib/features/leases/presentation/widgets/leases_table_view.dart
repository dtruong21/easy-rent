import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/lease.dart';
import '../../domain/lease_list_item.dart';
import '../lease_list_item_display_l10n.dart';
import 'lease_status_mapper.dart';

/// Colonnes triables du tableau baux.
enum _LeaseTableSort { property, tenant, startDate, amount }

/// Seule action du menu overflow "Régulariser les charges" (FEAT-030). Enum
/// à une valeur plutôt que `PopupMenuButton<void>` — `PopupMenuButton`
/// interprète une valeur sélectionnée `null` comme une ANNULATION (cf.
/// `PopupMenuButtonState.showButtonMenu` dans le SDK Flutter), donc
/// `onSelected` ne serait jamais appelé avec `PopupMenuItem<void>` (dont la
/// `value` par défaut est aussi `null`).
enum _LeaseTableMenuAction { regularizeCharges }

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
              DataColumn(
                label: Text(context.l10n.leasesTableColumnProperty),
                onSort: _onSort,
              ),
              DataColumn(
                label: Text(context.l10n.leasesTableColumnTenant),
                onSort: _onSort,
              ),
              DataColumn(label: Text(context.l10n.leasesTableColumnPeriod)),
              DataColumn(
                label: Text(context.l10n.leasesTableColumnRent),
                numeric: true,
                onSort: _onSort,
              ),
              DataColumn(label: Text(context.l10n.leasesTableColumnStatus)),
              DataColumn(label: Text(context.l10n.leasesTableColumnActions)),
            ],
            rows: items.map((item) => _buildRow(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, LeaseListItem item) {
    final lease = item.lease;
    final pillData = leaseStatusPill(context, lease, isLate: item.isLate);

    return DataRow(
      onSelectChanged: (_) => context.push('/leases/${lease.id}'),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
            child: Text(
              item.displayPropertyName(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
            child: Text(
              item.displayTenantName(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 200,
            child: Text(
              _formatPeriod(context, lease.startDate, lease.endDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(
            context.l10n.leasesTableRentCc(
              MoneyFormat.formatEurosFromCents(lease.totalAmountCents),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('table_receipts_${lease.id}'),
                onPressed: () => context.push('/leases/${lease.id}/receipts'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                tooltip: context.l10n.leasesCardReceiptsButton,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: Key('table_payment_${lease.id}'),
                onPressed: () =>
                    context.push('/leases/${lease.id}/payments/new'),
                icon: const Icon(Icons.add, size: 18),
                tooltip: context.l10n.leasesTableAddPaymentTooltip,
                visualDensity: VisualDensity.compact,
              ),
              // Raccourci "Régulariser les charges" (FEAT-030) — gate légal :
              // uniquement les baux en mode provisions (FEAT-042), cf.
              // commentaire équivalent dans lease_card.dart. Navigue vers la
              // fiche qui ouvre le dialog automatiquement (les données
              // riches requises ne sont pas portées par LeaseListItem).
              if (lease.canRegularizeCharges)
                PopupMenuButton<_LeaseTableMenuAction>(
                  key: Key('table_menu_${lease.id}'),
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: context.l10n.leasesCardActionsTooltip,
                  padding: EdgeInsets.zero,
                  onSelected: (_) =>
                      context.push('/leases/${lease.id}?action=regularize'),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: const Key('table_menu_item_regularize_charges'),
                      value: _LeaseTableMenuAction.regularizeCharges,
                      child: Text(context.l10n.leasesRegularizeChargesMenuItem),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPeriod(
    BuildContext context,
    DateTime startDate,
    DateTime? endDate,
  ) {
    final start = FrenchDate.format(startDate);
    if (endDate == null) {
      return context.l10n.leasesCardPeriodOpenEnded(start);
    }
    return context.l10n.leasesCardPeriod(start, FrenchDate.format(endDate));
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

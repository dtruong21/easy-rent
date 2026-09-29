import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../../../core/ui/filters/filter_chips_bar.dart';
import '../../application/receipts_filter_provider.dart';
import '../../domain/receipt_status_filter.dart';
import 'receipt_status_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Quittances.
///
/// Paramétrique par [leaseId] pour isoler l'état par bail.
///
/// Puces de filtre ([FilterChipsBar]) avec compteurs, sur toutes les
/// largeurs. En [trailing] (fixe à droite) : le sélecteur d'année (dès qu'au
/// moins une année est disponible) puis le [ViewModeToggle] (masqué sur
/// mobile, qui force la Timeline).
class ReceiptsFilterBar extends ConsumerWidget {
  const ReceiptsFilterBar({super.key, required this.leaseId});

  final String leaseId;

  String get _viewModeKey => 'receipts:$leaseId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(receiptStatusFilterProvider(leaseId));
    final currentYear = ref.watch(receiptYearFilterProvider(leaseId));
    final availableYears = ref.watch(receiptAvailableYearsProvider(leaseId));
    final counts = ref.watch(receiptStatusCountsProvider(leaseId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FilterChipsBar<ReceiptStatusFilter>(
        options: [
          for (final f in ReceiptStatusFilter.values)
            FilterChipOption(
              value: f,
              label: f.label(context),
              count: counts?[f],
            ),
        ],
        selected: currentFilter,
        onSelected: (f) =>
            ref.read(receiptStatusFilterProvider(leaseId).notifier).state = f,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (availableYears.isNotEmpty) ...[
              _YearDropdown(
                currentYear: currentYear,
                availableYears: availableYears,
                onChanged: (y) =>
                    ref
                            .read(receiptYearFilterProvider(leaseId).notifier)
                            .state =
                        y,
              ),
              const SizedBox(width: 12),
            ],
            if (!context.isMobile) ViewModeToggle(pageKey: _viewModeKey),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown Année
// ---------------------------------------------------------------------------

class _YearDropdown extends StatelessWidget {
  const _YearDropdown({
    required this.currentYear,
    required this.availableYears,
    required this.onChanged,
  });

  final int? currentYear;
  final List<int> availableYears;
  final void Function(int?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<int?>(
      key: const Key('receipt_year_filter'),
      value: currentYear,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: theme.textTheme.bodyMedium,
      hint: Text(context.l10n.receiptsFilterAllYears),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(context.l10n.receiptsFilterAllYears),
        ),
        ...availableYears.map(
          (y) => DropdownMenuItem<int?>(value: y, child: Text('$y')),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

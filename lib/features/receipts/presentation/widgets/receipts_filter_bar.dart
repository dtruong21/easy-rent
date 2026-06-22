import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode.dart';
import '../../../../core/ui/cards/view_mode_provider.dart';
import '../../application/receipts_filter_provider.dart';
import '../../domain/receipt_status_filter.dart';

/// Barre de filtres + toggle de vue pour la page Quittances.
///
/// Paramétrique par [leaseId] pour isoler l'état par bail.
///
/// - Mobile (< 600px) : Dropdown statut + pas de toggle (force Timeline).
/// - Tablette/desktop (>= 600px) : SegmentedButton statut + Dropdown année
///   + ViewModeToggle (Timeline | Cards).
class ReceiptsFilterBar extends ConsumerWidget {
  const ReceiptsFilterBar({super.key, required this.leaseId});

  final String leaseId;

  String get _viewModeKey => 'receipts:$leaseId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(receiptStatusFilterProvider(leaseId));
    final currentYear = ref.watch(receiptYearFilterProvider(leaseId));
    final availableYears = ref.watch(receiptAvailableYearsProvider(leaseId));
    final isMobile = context.isMobile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: isMobile
          ? _MobileFilterBar(
              leaseId: leaseId,
              currentFilter: currentFilter,
              onFilterChanged: (f) {
                if (f != null) {
                  ref
                          .read(receiptStatusFilterProvider(leaseId).notifier)
                          .state =
                      f;
                }
              },
            )
          : _DesktopFilterBar(
              leaseId: leaseId,
              viewModeKey: _viewModeKey,
              currentFilter: currentFilter,
              currentYear: currentYear,
              availableYears: availableYears,
              onFilterChanged: (f) {
                ref.read(receiptStatusFilterProvider(leaseId).notifier).state =
                    f;
              },
              onYearChanged: (y) {
                ref.read(receiptYearFilterProvider(leaseId).notifier).state = y;
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop / tablette
// ---------------------------------------------------------------------------

class _DesktopFilterBar extends ConsumerWidget {
  const _DesktopFilterBar({
    required this.leaseId,
    required this.viewModeKey,
    required this.currentFilter,
    required this.currentYear,
    required this.availableYears,
    required this.onFilterChanged,
    required this.onYearChanged,
  });

  final String leaseId;
  final String viewModeKey;
  final ReceiptStatusFilter currentFilter;
  final int? currentYear;
  final List<int> availableYears;
  final void Function(ReceiptStatusFilter) onFilterChanged;
  final void Function(int?) onYearChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(viewModeProvider(viewModeKey));

    return Row(
      children: [
        // Segmented button statut (4 segments).
        Expanded(
          child: SegmentedButton<ReceiptStatusFilter>(
            key: const Key('receipt_status_filter'),
            segments: ReceiptStatusFilter.values
                .map(
                  (f) => ButtonSegment<ReceiptStatusFilter>(
                    value: f,
                    label: Text(f.labelFr),
                  ),
                )
                .toList(),
            selected: {currentFilter},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) onFilterChanged(selection.first);
            },
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(width: 12),
        // Dropdown année.
        if (availableYears.isNotEmpty)
          _YearDropdown(
            currentYear: currentYear,
            availableYears: availableYears,
            onChanged: onYearChanged,
          ),
        if (availableYears.isNotEmpty) const SizedBox(width: 12),
        // Toggle Timeline / Cards.
        _ReceiptsViewModeToggle(
          viewModeKey: viewModeKey,
          currentMode: currentMode,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile
// ---------------------------------------------------------------------------

class _MobileFilterBar extends StatelessWidget {
  const _MobileFilterBar({
    required this.leaseId,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  final String leaseId;
  final ReceiptStatusFilter currentFilter;
  final void Function(ReceiptStatusFilter?) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<ReceiptStatusFilter>(
      key: const Key('receipt_status_filter_mobile'),
      value: currentFilter,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: theme.textTheme.bodyMedium,
      items: ReceiptStatusFilter.values
          .map(
            (f) => DropdownMenuItem<ReceiptStatusFilter>(
              value: f,
              child: Text(f.labelFr),
            ),
          )
          .toList(),
      onChanged: onFilterChanged,
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
      hint: const Text('Toutes années'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Toutes années')),
        ...availableYears.map(
          (y) => DropdownMenuItem<int?>(value: y, child: Text('$y')),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle Timeline / Cards (adapté au ViewMode existant)
// ---------------------------------------------------------------------------

/// Toggle "Timeline" / "Cards" pour la page Quittances.
///
/// Réutilise [viewModeProvider] avec le mapping :
/// - [ViewMode.table] → Timeline (vue par défaut)
/// - [ViewMode.card]  → Cards
///
/// Masqué sur mobile (< 600px).
class _ReceiptsViewModeToggle extends StatelessWidget {
  const _ReceiptsViewModeToggle({
    required this.viewModeKey,
    required this.currentMode,
  });

  final String viewModeKey;
  final ViewMode currentMode;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) {
        return SegmentedButton<ViewMode>(
          key: const Key('receipt_view_mode_toggle'),
          segments: const [
            ButtonSegment(
              value: ViewMode.table,
              icon: Icon(Icons.view_timeline_outlined),
              label: Text('Timeline'),
            ),
            ButtonSegment(
              value: ViewMode.card,
              icon: Icon(Icons.grid_view_outlined),
              label: Text('Cards'),
            ),
          ],
          selected: {currentMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              ref
                  .read(viewModeProvider(viewModeKey).notifier)
                  .setMode(selection.first);
            }
          },
          showSelectedIcon: false,
        );
      },
    );
  }
}

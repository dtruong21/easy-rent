import 'package:flutter/material.dart';

import '../../../core/utils/money_format.dart';
import '../application/expenses_provider.dart';
import '../domain/expense_category.dart';
import '../domain/expense_filter.dart';
import '../domain/expense_nature.dart';

/// Barre de filtres de l'historique des dépenses d'un bien.
///
/// Filtre par exercice (période de rattachement), catégorie et nature.
/// Affiche les totaux récupérable / non-récupérable de la sélection courante
/// séparément (jamais mélangés — décret n°87-713).
class ExpenseFilterBar extends StatelessWidget {
  const ExpenseFilterBar({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    required this.availableYears,
    required this.totals,
  });

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onFilterChanged;
  final List<int> availableYears;
  final ExpenseTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _YearDropdown(
                  key: const Key('filter_period_year'),
                  value: filter.periodYear,
                  availableYears: availableYears,
                  onChanged: (y) =>
                      onFilterChanged(filter.copyWith(periodYear: y)),
                ),
                _CategoryDropdown(
                  key: const Key('filter_category'),
                  value: filter.category,
                  onChanged: (c) =>
                      onFilterChanged(filter.copyWith(category: c)),
                ),
                _NatureDropdown(
                  key: const Key('filter_nature'),
                  value: filter.nature,
                  onChanged: (n) => onFilterChanged(filter.copyWith(nature: n)),
                ),
                if (filter.isActive)
                  TextButton.icon(
                    key: const Key('btn_reset_expense_filter'),
                    onPressed: () => onFilterChanged(ExpenseFilter.empty),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Réinitialiser'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _TotalColumn(
                  key: const Key('total_recoverable'),
                  label: 'Total récupérable',
                  amountCents: totals.recoverableCents,
                  color: Colors.teal.shade700,
                ),
                _TotalColumn(
                  key: const Key('total_non_recoverable'),
                  label: 'Total non récupérable',
                  amountCents: totals.nonRecoverableCents,
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YearDropdown extends StatelessWidget {
  const _YearDropdown({
    super.key,
    required this.value,
    required this.availableYears,
    required this.onChanged,
  });

  final int? value;
  final List<int> availableYears;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int?>(
      value: value,
      hint: const Text('Exercice'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Tous')),
        ...availableYears.map(
          (y) => DropdownMenuItem<int?>(value: y, child: Text('$y')),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ExpenseCategory? value;
  final ValueChanged<ExpenseCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ExpenseCategory?>(
      value: value,
      hint: const Text('Catégorie'),
      items: [
        const DropdownMenuItem<ExpenseCategory?>(
          value: null,
          child: Text('Toutes'),
        ),
        ...ExpenseCategory.values.map(
          (c) => DropdownMenuItem<ExpenseCategory?>(
            value: c,
            child: Text(c.label),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _NatureDropdown extends StatelessWidget {
  const _NatureDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ExpenseNature? value;
  final ValueChanged<ExpenseNature?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ExpenseNature?>(
      value: value,
      hint: const Text('Nature'),
      items: [
        const DropdownMenuItem<ExpenseNature?>(
          value: null,
          child: Text('Toutes'),
        ),
        ...ExpenseNature.values.map(
          (n) =>
              DropdownMenuItem<ExpenseNature?>(value: n, child: Text(n.label)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    super.key,
    required this.label,
    required this.amountCents,
    required this.color,
  });

  final String label;
  final int amountCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
          MoneyFormat.formatEurosFromCents(amountCents),
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

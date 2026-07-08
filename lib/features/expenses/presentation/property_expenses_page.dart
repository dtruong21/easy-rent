import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../properties/application/property_detail_provider.dart';
import '../application/expenses_provider.dart';
import '../domain/expense.dart';
import '../domain/expense_filter.dart';
import 'expense_filter_bar.dart';
import 'expense_list_tile.dart';

/// Historique des dépenses d'un bien — filtrable par exercice, catégorie et
/// nature. Totaux récupérable / non-récupérable affichés séparément.
///
/// Route : `/properties/:id/expenses`. Ouvert en `push()` (conserve la
/// stack, cohérent FEAT-030).
class PropertyExpensesPage extends ConsumerStatefulWidget {
  const PropertyExpensesPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyExpensesPage> createState() =>
      _PropertyExpensesPageState();
}

class _PropertyExpensesPageState extends ConsumerState<PropertyExpensesPage> {
  ExpenseFilter _filter = ExpenseFilter.empty;

  @override
  Widget build(BuildContext context) {
    final asyncProperty = ref.watch(propertyDetailProvider(widget.propertyId));
    final asyncExpenses = ref.watch(
      propertyExpensesProvider(widget.propertyId),
    );

    final title =
        asyncProperty.valueOrNull?.name ??
        context.l10n.expensesHistoryPageTitle;

    return Scaffold(
      appBar: AppAppBar(
        title: title,
        fallbackRoute: '/properties/${widget.propertyId}',
        actions: [
          IconButton(
            key: const Key('btn_add_expense_from_history'),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.expensesAddButton,
            onPressed: () =>
                context.push('/properties/${widget.propertyId}/expenses/new'),
          ),
        ],
      ),
      body: asyncExpenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(context.l10n.expensesListErrorMessage)),
        data: (expenses) => _Content(
          propertyId: widget.propertyId,
          expenses: expenses,
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.propertyId,
    required this.expenses,
    required this.filter,
    required this.onFilterChanged,
  });

  final String propertyId;
  final List<Expense> expenses;
  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final years = expenses.map((e) => e.periodYear).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final filtered = filter.apply(expenses);
    final totals = ExpenseTotals.fromExpenses(filtered);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpenseFilterBar(
            filter: filter,
            onFilterChanged: onFilterChanged,
            availableYears: years,
            totals: totals,
          ),
          const SizedBox(height: 24),
          if (filtered.isEmpty)
            const _EmptyState()
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final expense = filtered[index];
                  return ExpenseListTile(
                    expense: expense,
                    onTap: () => context.push(
                      '/properties/$propertyId/expenses/${expense.id}/edit',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.expensesEmptyFilterMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

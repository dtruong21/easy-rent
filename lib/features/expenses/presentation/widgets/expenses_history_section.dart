import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/money_format.dart';
import '../../application/expenses_provider.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../expense_category_l10n.dart';

/// Carte résumé des dépenses affichée sur [PropertyDetailPage].
///
/// Placée entre la carte Rentabilité et la section Baux (cf. plan
/// § h) "Fiche bien"). Affiche le total des 12 derniers mois (récupérable /
/// non-récupérable séparés) + CTA « Ajouter une dépense » et
/// « Voir l'historique ».
class ExpensesHistorySection extends ConsumerWidget {
  const ExpensesHistorySection({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncExpenses = ref.watch(propertyExpensesProvider(propertyId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.expensesHistorySectionTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const Key('btn_view_expenses_history'),
                  onPressed: () =>
                      context.push('/properties/$propertyId/expenses'),
                  child: Text(context.l10n.expensesHistoryViewAllButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            asyncExpenses.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                context.l10n.expensesHistoryLoadErrorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (expenses) => _Summary(expenses: expenses),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('btn_add_expense_from_history_section'),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.expensesAddButton),
              onPressed: () =>
                  context.push('/properties/$propertyId/expenses/new'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 365));
    // Fenêtre de temps, pas filtre de lignes : une charge trimestrielle
    // compte ses quatre échéances de l'année (FEAT-041d), une dépense
    // ponctuelle compte une fois si sa date tombe dans la fenêtre.
    final totals = ExpenseTotals.overWindow(
      expenses: expenses,
      from: cutoff,
      to: now,
    );

    if (expenses.isEmpty) {
      return Text(
        context.l10n.expensesHistoryEmptyMessage,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.expensesHistoryLast12MonthsLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _TotalChip(
              key: const Key('summary_total_recoverable'),
              label: ExpenseCategory.recoverable.localizedLabel(context),
              amountCents: totals.recoverableCents,
              color: Colors.teal.shade700,
            ),
            _TotalChip(
              key: const Key('summary_total_non_recoverable'),
              label: ExpenseCategory.nonRecoverable.localizedLabel(context),
              amountCents: totals.nonRecoverableCents,
              color: theme.colorScheme.error,
            ),
          ],
        ),
      ],
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({
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
        Text(
          MoneyFormat.formatEurosFromCents(amountCents),
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/utils/french_date.dart';
import '../../../core/utils/money_format.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';

/// Tuile d'une dépense dans l'historique d'un bien.
///
/// Affiche : icône de nature, libellé nature, chip catégorie
/// récupérable/non-récupérable, montant, date, indicateur visuel de
/// justificatif s'il existe ([Expense.hasDocument]).
///
/// ⚠️ L'ouverture du justificatif (signed URL `getDocumentDownloadUrl`)
/// reste un follow-up : ce bloc affiche seulement l'icône de présence, le
/// justificatif se consulte pour l'instant via la fiche d'édition
/// (`documentId` transmis, FEAT-041b).
class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({super.key, required this.expense, this.onTap});

  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('expense_tile_${expense.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          expense.nature.icon,
          color: theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(expense.nature.label),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _CategoryChip(category: expense.category),
          Text(
            '· ${FrenchDate.format(expense.expenseDate)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (expense.hasDocument)
            Icon(
              Icons.attach_file,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      trailing: Text(
        MoneyFormat.formatEurosFromCents(expense.amountCents),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final ExpenseCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category.chipColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        category.label,
        style: theme.textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

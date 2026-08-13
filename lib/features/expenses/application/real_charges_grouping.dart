import '../../../core/finance/real_expense_charges.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_nature.dart';

/// Regroupe des dépenses actives (déjà filtrées `deletedAt == null` par le
/// repository) en [PropertyRealCharges] — projette [Expense] (qui importe
/// transitivement Flutter via `ExpenseNature`/`ExpenseCategory`) vers les
/// types purs consommés par `core/finance` (cf. tête de fichier
/// `real_expense_charges.dart`).
///
/// Seules les dépenses **non récupérables** sont retenues : les charges
/// récupérables sont refacturées au locataire via la régularisation
/// annuelle, elles ne représentent pas une sortie de cash flow nette pour
/// le bailleur. Seules les 3 natures ayant un équivalent prévisionnel
/// déclaré sur le bien sont regroupées (`property_tax`, `insurance_pno`,
/// `condo_charges`) — les autres (`works`, `repair_maintenance`,
/// `management_fees`, `other`) n'ont pas de champ déclaré équivalent et
/// restent hors du calcul de cash flow dans cette itération.
///
/// La périodicité (FEAT-041d) est transportée telle quelle : c'est
/// `profitability.dart` qui décide de son effet (bascule immédiate sur le
/// réel + montant annualisé tant que la récurrence est en cours).
PropertyRealCharges groupRealCharges(Iterable<Expense> expenses) {
  final propertyTax = <RealChargeEntry>[];
  final insurancePno = <RealChargeEntry>[];
  final condoFeesNonRecoverable = <RealChargeEntry>[];

  for (final expense in expenses) {
    if (expense.category != ExpenseCategory.nonRecoverable) continue;
    final entry = RealChargeEntry(
      amountCents: expense.amountCents,
      expenseDate: expense.expenseDate,
      recurrence: expense.recurrence,
      recurrenceEndDate: expense.recurrenceEndDate,
    );
    switch (expense.nature) {
      case ExpenseNature.propertyTax:
        propertyTax.add(entry);
      case ExpenseNature.insurancePno:
        insurancePno.add(entry);
      case ExpenseNature.condoCharges:
        condoFeesNonRecoverable.add(entry);
      case ExpenseNature.managementFees:
      case ExpenseNature.works:
      case ExpenseNature.repairMaintenance:
      case ExpenseNature.other:
        break;
    }
  }

  return PropertyRealCharges(
    propertyTax: propertyTax,
    insurancePno: insurancePno,
    condoFeesNonRecoverable: condoFeesNonRecoverable,
  );
}

/// Variante multi-biens pour l'agrégation portfolio (dashboard) : une seule
/// requête Firestore landlord-wide (voir
/// `ExpensesRepository.listAllForLandlord`) est groupée par `propertyId`
/// puis par nature — évite une requête de dépenses par bien.
Map<String, PropertyRealCharges> groupRealChargesByProperty(
  Iterable<Expense> expenses,
) {
  final byProperty = <String, List<Expense>>{};
  for (final expense in expenses) {
    byProperty.putIfAbsent(expense.propertyId, () => []).add(expense);
  }
  return byProperty.map(
    (propertyId, list) => MapEntry(propertyId, groupRealCharges(list)),
  );
}

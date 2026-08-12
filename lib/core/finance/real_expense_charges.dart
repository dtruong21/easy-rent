/// Types purs (aucune dépendance Flutter/Firebase) alimentant le calcul de
/// cash flow réel de `profitability.dart`.
///
/// Volontairement découplés du modèle `Expense`
/// (`features/expenses/domain/expense.dart`) : ce dernier importe
/// transitivement `package:flutter/material.dart` (icônes/couleurs portées
/// par `ExpenseNature`/`ExpenseCategory`), ce qui casserait la promesse
/// « aucune dépendance Flutter » de `profitability.dart`. C'est à la couche
/// application (ex. `features/expenses/application/`) de projeter les
/// `Expense` vers ces types minimaux — voir `groupRealCharges`.
library;

/// Entrée minimale d'une dépense réelle : montant + date d'engagement.
typedef RealChargeEntry = ({int amountCents, DateTime expenseDate});

/// Dépenses réelles **non récupérables** d'un bien, déjà regroupées par
/// nature de charge ayant un équivalent prévisionnel déclaré sur la fiche
/// du bien.
///
/// Seules 3 natures ont un tel équivalent (`Property.propertyTaxAnnualCents`,
/// `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`) : c'est
/// uniquement pour celles-ci qu'un remplacement du prévisionnel par le réel
/// a un sens (sinon rien à remplacer, donc pas de risque de double
/// comptage — cf. doc de tête de fichier `profitability.dart`). Les autres
/// natures de dépense (travaux, entretien, honoraires de gestion, autre)
/// n'ont pas de champ déclaré équivalent : elles restent hors du calcul de
/// cash flow dans cette itération.
class PropertyRealCharges {
  const PropertyRealCharges({
    this.propertyTax = const [],
    this.insurancePno = const [],
    this.condoFeesNonRecoverable = const [],
  });

  /// Aucune dépense réelle exploitable — le cash flow repose entièrement
  /// sur le prévisionnel déclaré (comportement historique).
  static const PropertyRealCharges empty = PropertyRealCharges();

  /// Dépenses de nature `property_tax`, catégorie non-récupérable.
  final List<RealChargeEntry> propertyTax;

  /// Dépenses de nature `insurance_pno`, catégorie non-récupérable.
  final List<RealChargeEntry> insurancePno;

  /// Dépenses de nature `condo_charges` **overridées** en non-récupérable
  /// (la nature `condo_charges` est récupérable par défaut — cf.
  /// `ExpenseNature.defaultCategory` — donc seule la portion explicitement
  /// classée non-récupérable par le bailleur entre dans ce bucket).
  final List<RealChargeEntry> condoFeesNonRecoverable;
}

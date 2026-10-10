// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/finance/expense_recurrence.dart';
import 'expense_category.dart';
import 'expense_nature.dart';

part 'expense.freezed.dart';
part 'expense.g.dart';

/// Modèle immutable d'une dépense — entité first-class « l'argent qui sort ».
///
/// Mappé sur la collection Firestore `expenses` (camelCase, ponté snake_case
/// via `firestoreDocToSnakeJson`, pattern `Property`/`Payment`/`Document`).
/// Collection **CF-EXCLUSIVE** : toute écriture passe par les Callables
/// `createExpense`/`updateExpense`/`softDeleteEntity` — voir
/// `docs/plans/FEAT-041-depenses.md` § a)/b).
///
/// [category] est **dérivée serveur** de [nature] (garde-fou juridique
/// décret n°87-713) — jamais forgée côté client.
///
/// [amountCents] est toujours en centimes (int), jamais de `double`.
@freezed
class Expense with _$Expense {
  const factory Expense({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'property_id') required String propertyId,
    @JsonKey(name: 'property_name') String? propertyName,
    @JsonKey(name: 'lease_id') String? leaseId,
    @JsonKey(name: 'tenant_last_name') String? tenantLastName,
    @JsonKey(name: 'amount_cents') required int amountCents,
    @JsonKey(name: 'expense_date') required DateTime expenseDate,
    @JsonKey(fromJson: _natureFromJson, toJson: _natureToJson)
    required ExpenseNature nature,
    @JsonKey(fromJson: _categoryFromJson, toJson: _categoryToJson)
    required ExpenseCategory category,
    @JsonKey(name: 'category_overridden')
    @Default(false)
    bool categoryOverridden,
    @JsonKey(name: 'period_year') required int periodYear,
    @JsonKey(name: 'period_start') DateTime? periodStart,
    @JsonKey(name: 'period_end') DateTime? periodEnd,
    @JsonKey(fromJson: _recurrenceFromJson, toJson: _recurrenceToJson)
    @Default(ExpenseRecurrence.none)
    ExpenseRecurrence recurrence,
    @JsonKey(name: 'recurrence_end_date') DateTime? recurrenceEndDate,
    @JsonKey(name: 'document_id') String? documentId,
    String? notes,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Expense;

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);
}

// ---------------------------------------------------------------------------
// Helpers JSON privés
// ---------------------------------------------------------------------------

ExpenseNature _natureFromJson(dynamic value) =>
    ExpenseNature.fromSql(value as String);

String _natureToJson(ExpenseNature nature) => nature.sqlValue;

ExpenseCategory _categoryFromJson(dynamic value) =>
    ExpenseCategory.fromSql(value as String);

String _categoryToJson(ExpenseCategory category) => category.sqlValue;

/// Tolère l'absence du champ : les dépenses créées avant FEAT-041d n'ont pas
/// de `recurrence` en base et restent ponctuelles — aucune migration.
ExpenseRecurrence _recurrenceFromJson(dynamic value) =>
    ExpenseRecurrence.fromSql(value as String?);

String _recurrenceToJson(ExpenseRecurrence recurrence) => recurrence.sqlValue;

// ---------------------------------------------------------------------------
// Extension — getters calculés (non freezed pour éviter le codegen)
// ---------------------------------------------------------------------------

/// Getters utilitaires sur une dépense.
extension ExpenseX on Expense {
  /// Vrai si la dépense est récupérable auprès du locataire.
  bool get isRecoverable => category == ExpenseCategory.recoverable;

  /// Vrai si un justificatif est attaché à cette dépense.
  bool get hasDocument => documentId != null;

  /// Vrai si la dépense revient périodiquement (FEAT-041d).
  bool get isRecurring => recurrence.isRecurring;

  /// Échéances de cette dépense tombant dans `[from, to]` (bornes incluses).
  ///
  /// Une dépense ponctuelle en produit au plus une (sa date). Une dépense
  /// récurrente en produit une par période, **jamais avant [expenseDate]**
  /// ni après [recurrenceEndDate] — cf. `core/finance/expense_recurrence.dart`.
  List<DateTime> occurrencesBetween(DateTime from, DateTime to) =>
      expenseOccurrences(
        firstOccurrence: expenseDate,
        recurrence: recurrence,
        endDate: recurrenceEndDate,
        from: from,
        to: to,
      );
}

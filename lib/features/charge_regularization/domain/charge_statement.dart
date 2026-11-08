// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'charge_regularization_balance.dart';
import 'charge_statement_line_item.dart';

part 'charge_statement.freezed.dart';
part 'charge_statement.g.dart';

/// Décompte de régularisation de charges figé et immuable (FEAT-033).
///
/// Snapshot légal (art. 23 loi 6/7/1989) créé par la callable
/// `finalizeChargeRegularization` — reproductible à l'identique, jamais
/// re-synchronisé même si les Dépenses ou paiements sources changent. Miroir
/// du modèle `Receipt`. Le PDF est rendu côté client à partir de ces champs
/// figés (aucun PDF serveur).
@freezed
class ChargeStatement with _$ChargeStatement {
  const ChargeStatement._();

  const factory ChargeStatement({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(name: 'property_id') required String propertyId,
    @JsonKey(name: 'landlord_full_name') required String landlordFullName,
    @JsonKey(name: 'landlord_address') required String landlordAddress,
    @JsonKey(name: 'tenant_full_name') required String tenantFullName,
    @JsonKey(name: 'tenant_first_name') required String tenantFirstName,
    @JsonKey(name: 'property_name') required String propertyName,
    @JsonKey(name: 'property_address') required String propertyAddress,
    @JsonKey(name: 'period_start') required DateTime periodStart,
    @JsonKey(name: 'period_end') required DateTime periodEnd,
    @JsonKey(name: 'provisions_collected_cents')
    required int provisionsCollectedCents,
    @JsonKey(name: 'actual_expenses_cents') required int actualExpensesCents,
    @JsonKey(name: 'actual_expenses_source')
    required String actualExpensesSource,
    @JsonKey(name: 'balance_cents') required int balanceCents,
    @JsonKey(name: 'line_items')
    @Default(<ChargeStatementLineItem>[])
    List<ChargeStatementLineItem> lineItems,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'is_voided') @Default(false) bool isVoided,
    @JsonKey(name: 'voided_at') DateTime? voidedAt,
    @JsonKey(name: 'voided_reason') String? voidedReason,
    @JsonKey(name: 'sent_at') DateTime? sentAt,
    @JsonKey(name: 'sent_to_email') String? sentToEmail,
    @JsonKey(name: 'schema_version') @Default(1) int schemaVersion,
  }) = _ChargeStatement;

  factory ChargeStatement.fromJson(Map<String, dynamic> json) =>
      _$ChargeStatementFromJson(json);

  bool get hasLineItems => lineItems.isNotEmpty;
  bool get isSent => sentAt != null;

  int get balanceAbsCents => balanceCents.abs();

  /// Sens du solde, dérivé du signe (source de vérité unique = balanceCents).
  ChargeRegularizationBalanceDirection get direction {
    if (balanceCents > 0) {
      return ChargeRegularizationBalanceDirection.dueByTenant;
    }
    if (balanceCents < 0) {
      return ChargeRegularizationBalanceDirection.dueToTenant;
    }
    return ChargeRegularizationBalanceDirection.balanced;
  }

  String get labelFr => direction.labelFr;
}

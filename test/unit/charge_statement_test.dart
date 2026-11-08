import 'package:easyrent/features/charge_regularization/domain/charge_statement.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> baseJson() => {
    'id': 'cs-1',
    'landlord_id': 'lord1',
    'lease_id': 'l1',
    'property_id': 'p1',
    'landlord_full_name': 'Jean Bailleur',
    'landlord_address': '1 rue A',
    'tenant_full_name': 'Marie Loc',
    'tenant_first_name': 'Marie',
    'property_name': 'Studio',
    'property_address': '2 rue B',
    'period_start': '2025-01-01T00:00:00.000Z',
    'period_end': '2025-12-31T00:00:00.000Z',
    'provisions_collected_cents': 12000,
    'actual_expenses_cents': 15000,
    'actual_expenses_source': 'manual',
    'balance_cents': 3000,
    'line_items': <dynamic>[],
    'created_at': '2026-01-05T10:00:00.000Z',
    'is_voided': false,
    'voided_at': null,
    'voided_reason': null,
    'sent_at': null,
    'sent_to_email': null,
    'schema_version': 1,
  };

  test('fromJson mappe les champs snake_case', () {
    final s = ChargeStatement.fromJson(baseJson());
    expect(s.id, 'cs-1');
    expect(s.provisionsCollectedCents, 12000);
    expect(s.actualExpensesCents, 15000);
    expect(s.balanceCents, 3000);
    expect(s.isVoided, isFalse);
    expect(s.hasLineItems, isFalse);
  });

  test('direction dérivée du solde signé', () {
    expect(
      ChargeStatement.fromJson(baseJson()).direction,
      ChargeRegularizationBalanceDirection.dueByTenant,
    );
    expect(
      ChargeStatement.fromJson({
        ...baseJson(),
        'balance_cents': -500,
      }).direction,
      ChargeRegularizationBalanceDirection.dueToTenant,
    );
    expect(
      ChargeStatement.fromJson({...baseJson(), 'balance_cents': 0}).direction,
      ChargeRegularizationBalanceDirection.balanced,
    );
  });

  test('balanceAbsCents toujours positif', () {
    expect(
      ChargeStatement.fromJson({
        ...baseJson(),
        'balance_cents': -500,
      }).balanceAbsCents,
      500,
    );
  });

  test('line_items désérialisés', () {
    final s = ChargeStatement.fromJson({
      ...baseJson(),
      'actual_expenses_source': 'expenses',
      'line_items': [
        {
          'expense_id': 'e1',
          'nature': 'condo_charges',
          'notes': 'T1',
          'amount_cents': 15000,
          'expense_date': '2025-06-01T00:00:00.000Z',
        },
      ],
    });
    expect(s.hasLineItems, isTrue);
    expect(s.lineItems.single.amountCents, 15000);
    expect(s.lineItems.single.nature, 'condo_charges');
  });
}

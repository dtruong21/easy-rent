import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/payments/application/lease_payments_provider.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/tenants/application/tenant_leases_provider.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_punctuality_indicator.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._byLease);
  final Map<String, List<Payment>> _byLease;
  @override
  Future<List<Payment>> build(String arg) async => _byLease[arg] ?? const [];
}

Payment _pay({
  required String leaseId,
  required DateTime periodStart,
  required DateTime paidAt,
}) => Payment(
  id: '$leaseId-${periodStart.month}',
  leaseId: leaseId,
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  paymentMethod: PaymentMethod.virement,
  createdAt: periodStart,
  updatedAt: periodStart,
);

Widget _wrap({
  required List<Map<String, dynamic>> leases,
  required Map<String, List<Payment>> byLease,
}) => ProviderScope(
  overrides: [
    tenantLeasesProvider('t1').overrideWith((ref) async => leases),
    leasePaymentsProvider.overrideWith(() => _FakePayments(byLease)),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const Scaffold(body: TenantPunctualityIndicator(tenantId: 't1')),
  ),
);

void main() {
  testWidgets('agrège la ponctualité sur plusieurs baux (large → ligne)', (
    tester,
  ) async {
    // paymentDay=5, échéance = 5 du mois ; à l'heure si paidAt <= 5+5j = 10.
    final onTime = DateTime(2026, 1, 8); // <= 10 janv → à l'heure
    final late = DateTime(2026, 1, 20); // > 10 janv → en retard
    await tester.pumpWidget(
      _wrap(
        leases: const [
          {'id': 'l1', 'payment_day': 5},
          {'id': 'l2', 'payment_day': 5},
        ],
        byLease: {
          'l1': [
            _pay(
              leaseId: 'l1',
              periodStart: DateTime(2026, 1, 1),
              paidAt: onTime,
            ),
            _pay(
              leaseId: 'l1',
              periodStart: DateTime(2026, 2, 1),
              paidAt: DateTime(2026, 2, 8),
            ),
          ],
          'l2': [
            _pay(
              leaseId: 'l2',
              periodStart: DateTime(2026, 1, 1),
              paidAt: late,
            ),
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    // 3 paiements, 2 à l'heure → ligne complète visible (largeur test par défaut ≥ 600).
    expect(find.byKey(const Key('payment_punctuality_line')), findsOneWidget);
    expect(find.textContaining('2/3'), findsOneWidget);
  });

  testWidgets('aucun paiement sur les baux → rien', (tester) async {
    await tester.pumpWidget(
      _wrap(
        leases: const [
          {'id': 'l1', 'payment_day': 5},
        ],
        byLease: const {'l1': []},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_line')), findsNothing);
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
  });

  testWidgets('aucun bail → rien', (tester) async {
    await tester.pumpWidget(_wrap(leases: const [], byLease: const {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_tap')), findsNothing);
  });
}

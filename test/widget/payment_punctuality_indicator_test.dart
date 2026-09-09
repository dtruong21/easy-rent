import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/payments/application/lease_payments_provider.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_punctuality_indicator.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._items);
  final List<Payment> _items;
  @override
  Future<List<Payment>> build(String arg) async => _items;
}

Payment _pay(DateTime periodStart, DateTime paidAt) => Payment(
  id: 'p-${paidAt.millisecondsSinceEpoch}',
  leaseId: 'l1',
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
);

Widget _wrap(List<Payment> payments, {required double width}) => ProviderScope(
  overrides: [
    leasePaymentsProvider.overrideWith(() => _FakePayments(payments)),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: const Scaffold(
        body: PaymentPunctualityIndicator(leaseId: 'l1', paymentDay: 5),
      ),
    ),
  ),
);

void main() {
  final onTime = _pay(DateTime(2026, 3, 1), DateTime(2026, 3, 3));
  final late = _pay(DateTime(2026, 4, 1), DateTime(2026, 4, 30));

  testWidgets('large → ligne complète', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_line')), findsOneWidget);
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
  });

  testWidgets('mobile → pill compact', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_pill')), findsOneWidget);
  });

  testWidgets('tap → feuille de détail', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment_punctuality_tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_sheet')), findsOneWidget);
  });

  testWidgets('aucun paiement → texte neutre, pas de pill/ligne', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap([], width: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
    expect(find.byKey(const Key('payment_punctuality_line')), findsNothing);
  });
}

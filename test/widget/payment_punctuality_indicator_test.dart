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

  testWidgets('largeur tablette (~700px) → ligne complète sans overflow', (
    tester,
  ) async {
    // ≥3 paiements dont au moins un en retard : le libellé le plus long
    // possible ("N/M à l'heure · K en retard · P %") doit s'ellipser plutôt
    // que déborder (RenderFlex overflow) à une largeur tablette.
    final onTime2 = _pay(DateTime(2026, 5, 1), DateTime(2026, 5, 2));
    await tester.pumpWidget(_wrap([onTime, late, onTime2], width: 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('payment_punctuality_line')), findsOneWidget);
  });

  testWidgets('aucun paiement → texte neutre, pas de pill/ligne', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap([], width: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
    expect(find.byKey(const Key('payment_punctuality_line')), findsNothing);
  });

  testWidgets(
    'pill compact sur mobile étroit (~360px) avec long libellé → pas d\'overflow',
    (tester) async {
      // 30 paiements dont 6 en retard → libellé long ("24/30 · 6 retard"),
      // rendu dans le header (titre de section + bouton "Ajouter") à une
      // largeur mobile étroite : la pill doit s'ellipser plutôt que déborder.
      final many = List<Payment>.generate(30, (i) {
        final periodStart = DateTime(2026, 1 + i, 1);
        // paymentDay: 5 (voir _wrap) → échéance le 5 du mois de periodStart.
        final due = DateTime(periodStart.year, periodStart.month, 5);
        final isLate = i < 6;
        final paidAt = isLate
            ? due.add(const Duration(days: 20))
            : due.add(const Duration(days: 1));
        return _pay(periodStart, paidAt);
      });
      await tester.pumpWidget(_wrap(many, width: 360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('payment_punctuality_pill')), findsOneWidget);
    },
  );
}

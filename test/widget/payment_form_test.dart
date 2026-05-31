/// Tests widget de [PaymentForm] et [PaymentAmountWarning].
///
/// Couvre : pré-remplissage depuis bail, warning montant inférieur/supérieur,
/// validation (validateAll retourne false si champs vides).
library;

import 'package:easyrent/core/utils/money_format.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_amount_warning.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildPaymentForm({
  required TextEditingController rentCtrl,
  required TextEditingController chargesCtrl,
  required int leaseTotalCents,
  required int leaseRentCents,
  DateTime? initialPeriodStart,
  DateTime? initialPeriodEnd,
  DateTime? initialPaidAt,
  PaymentMethod? initialPaymentMethod,
  String? initialNotes,
  bool enabled = true,
  GlobalKey<PaymentFormWidgetState>? formKey,
}) {
  final gk = GlobalKey<FormState>();
  final wk = formKey ?? GlobalKey<PaymentFormWidgetState>();
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PaymentForm(
          key: wk,
          formKey: gk,
          rentController: rentCtrl,
          chargesController: chargesCtrl,
          leaseTotalCents: leaseTotalCents,
          leaseRentCents: leaseRentCents,
          initialPeriodStart: initialPeriodStart,
          initialPeriodEnd: initialPeriodEnd,
          initialPaidAt: initialPaidAt,
          initialPaymentMethod: initialPaymentMethod,
          initialNotes: initialNotes,
          enabled: enabled,
          onPeriodStartChanged: (_) {},
          onPeriodEndChanged: (_) {},
          onPaidAtChanged: (_) {},
          onPaymentMethodChanged: (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  group('PaymentForm — champs présents', () {
    testWidgets('champ loyer présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_rent')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ charges présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_charges')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ mode de paiement présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_payment_method')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ début de période présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_period_start')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ fin de période présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_period_end')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ date de paiement présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_paid_at')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — pré-remplissage depuis bail', () {
    testWidgets('loyer pré-rempli depuis bail (850,00)', (tester) async {
      final rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(85000),
      );
      final chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(5000),
      );
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.text('850,00'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('charges pré-remplies depuis bail (50,00)', (tester) async {
      final rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(85000),
      );
      final chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(5000),
      );
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.text('50,00'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('date de début de période pré-remplie', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
          initialPeriodStart: DateTime(2024, 1, 1),
        ),
      );
      expect(find.text('01/01/2024'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — warnings montant', () {
    testWidgets('pas de warning si montant égal au bail', (tester) async {
      // 85000 + 5000 = 90000 = leaseTotalCents
      final rentCtrl = TextEditingController(text: '850,00');
      final chargesCtrl = TextEditingController(text: '50,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_below')), findsNothing);
      expect(find.byKey(const Key('warning_amount_above')), findsNothing);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('warning "inférieur" si montant < bail', (tester) async {
      // 500 + 0 = 500 < 90000
      final rentCtrl = TextEditingController(text: '5,00');
      final chargesCtrl = TextEditingController(text: '0,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_below')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('warning "supérieur" si montant > bail', (tester) async {
      // 2000 + 0 = 200000 > 90000
      final rentCtrl = TextEditingController(text: '2000,00');
      final chargesCtrl = TextEditingController(text: '0,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_above')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — validateAll', () {
    testWidgets('validateAll retourne false si champs vides', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      final wk = GlobalKey<PaymentFormWidgetState>();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
          formKey: wk,
        ),
      );
      final result = wk.currentState?.validateAll() ?? true;
      await tester.pump();
      expect(result, isFalse);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentAmountWarning', () {
    testWidgets('type below affiche message inférieur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentAmountWarning(type: PaymentAmountWarningType.below),
          ),
        ),
      );
      expect(find.textContaining('inférieur'), findsOneWidget);
    });

    testWidgets('type above affiche message supérieur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentAmountWarning(type: PaymentAmountWarningType.above),
          ),
        ),
      );
      expect(find.textContaining('supérieur'), findsOneWidget);
    });
  });
}

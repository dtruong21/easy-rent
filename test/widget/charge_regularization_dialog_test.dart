/// Tests widget de [ChargeRegularizationDialog] (FEAT-029 V1.2).
///
/// Couvre :
/// - pré-remplissage automatique des provisions encaissées (somme des
///   `chargesAmountCents` des paiements du bail sur la période par défaut)
/// - recalcul du solde en direct à la saisie des dépenses réelles
/// - libellé signé affiché selon le sens du solde
/// - correctifs review : bouton "Générer et partager" désactivé tant que les
///   paiements ne sont pas chargés (état loading), et désactivé + message
///   d'erreur si la période de référence est inversée (fin <= début)
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/utils/money_format.dart';
import 'package:easyrent/features/charge_regularization/presentation/widgets/charge_regularization_dialog.dart';
import 'package:easyrent/features/expenses/data/expenses_repository.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake PaymentRepository
// ---------------------------------------------------------------------------

class _FakePaymentRepo implements PaymentRepository {
  const _FakePaymentRepo(this._payments) : _pending = null;

  /// Constructeur alternatif : ne résout JAMAIS `listForLease` — utilisé pour
  /// figer `leasePaymentsProvider` en état `loading` dans les tests
  /// (correctif review point 1).
  const _FakePaymentRepo.pending() : _payments = const [], _pending = true;

  final List<Payment> _payments;
  final bool? _pending;

  @override
  Future<List<Payment>> listForLease(String leaseId) {
    if (_pending == true) return Completer<List<Payment>>().future;
    return Future.value(_payments);
  }

  @override
  Future<Payment> getById(String id) async =>
      throw PaymentNotFoundException(id);

  @override
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  }) async => throw UnimplementedError();

  @override
  Future<Payment> update(Payment payment) async => throw UnimplementedError();

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Fake ExpensesRepository (FEAT-041c) — pilote le stream de dépenses
// récupérables consommé par `recoverableExpensesProvider`.
// ---------------------------------------------------------------------------

class _FakeExpensesRepo implements ExpensesRepository {
  const _FakeExpensesRepo([this._expenses = const []]);

  final List<Expense> _expenses;

  @override
  Stream<List<Expense>> watchForProperty(String propertyId) =>
      Stream.value(_expenses);

  @override
  Future<List<Expense>> listForProperty(String propertyId) async => _expenses;

  @override
  Future<Expense> getById(String id) async => throw UnimplementedError();

  @override
  Future<Expense> create({
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    String? documentId,
    String? notes,
  }) async => throw UnimplementedError();

  @override
  Future<Expense> update(Expense expense) async => throw UnimplementedError();

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Mock WebShareService — jamais réellement invoqué dans ces tests (on ne
// clique pas "Générer et partager"), mais requis pour que le provider soit
// résolvable si le widget le lit de façon anticipée.
// ---------------------------------------------------------------------------

class _MockWebShare implements WebShareService {
  const _MockWebShare();

  @override
  bool canShareFiles() => false;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {}

  @override
  Future<bool> copyToClipboard(String text) async => true;

  @override
  Future<List<int>> fetchBytes(String url) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Payment _makePayment({
  required String id,
  required DateTime periodStart,
  required DateTime periodEnd,
  required int chargesAmountCents,
}) => Payment(
  id: id,
  leaseId: 'lease-1',
  landlordId: 'landlord-1',
  periodStart: periodStart,
  periodEnd: periodEnd,
  paidAt: periodStart,
  rentAmountCents: 80000,
  chargesAmountCents: chargesAmountCents,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Expense _makeExpense({
  required String id,
  String propertyId = 'prop-1',
  String? leaseId = 'lease-1',
  required DateTime periodStart,
  required DateTime periodEnd,
  required int amountCents,
  ExpenseCategory category = ExpenseCategory.recoverable,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: propertyId,
  leaseId: leaseId,
  amountCents: amountCents,
  expenseDate: periodStart,
  nature: ExpenseNature.condoCharges,
  category: category,
  periodYear: periodStart.year,
  periodStart: periodStart,
  periodEnd: periodEnd,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildDialog({
  required List<Payment> payments,
  List<Expense> expenses = const [],
  PaymentRepository? paymentRepository,
  ExpensesRepository? expensesRepository,
}) {
  return ProviderScope(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(
        paymentRepository ?? _FakePaymentRepo(payments),
      ),
      expensesRepositoryProvider.overrideWithValue(
        expensesRepository ?? _FakeExpensesRepo(expenses),
      ),
      webShareServiceProvider.overrideWithValue(const _MockWebShare()),
    ],
    child: MaterialApp(
      // AppTheme.light requis : StatusPill (résumé du solde dans le dialog)
      // lit l'extension AppColors — absente du ThemeData par défaut.
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ChargeRegularizationDialog(
                leaseId: 'lease-1',
                propertyId: 'prop-1',
                landlordFullName: 'Marie Martin',
                landlordAddress: '1 rue de Paris, 75001 Paris',
                tenantFullName: 'Jean Dupont',
                tenantFirstName: 'Jean',
                propertyAddress: '2 rue de Lyon, 69001 Lyon',
                tenantEmail: 'jean.dupont@example.com',
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChargeRegularizationDialog — pré-remplissage des provisions', () {
    testWidgets(
      '12 mensualités de 100,00 € de charges sur les 12 derniers mois '
      'glissants → provisions pré-remplies à 1 200,00 €',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        // Paiement unique dont la période couvre exactement la fenêtre par
        // défaut du dialog (12 derniers mois glissants) — évite toute
        // dépendance à la date d'exécution du test pour construire 12
        // paiements mensuels distincts.
        final payments = [
          _makePayment(
            id: 'p1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            chargesAmountCents: 120000,
          ),
        ];

        await tester.pumpWidget(_buildDialog(payments: payments));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        // Le formateur FR (`MoneyFormat`) utilise une espace fine insécable
        // (U+202F) comme séparateur de milliers — visuellement identique à
        // une espace normale mais un code point distinct. Comparer via
        // `MoneyFormat.formatEurosFromCents` directement (plutôt que coder
        // en dur "1 200,00" avec une espace ASCII) évite un faux négatif.
        expect(
          find.textContaining(MoneyFormat.formatEurosFromCents(120000)),
          findsWidgets,
        );
      },
    );

    testWidgets('aucun paiement sur la période → provisions à 0,00 €', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(payments: const []));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(MoneyFormat.formatEurosFromCents(0)),
        findsWidgets,
      );
    });

    testWidgets('paiement hors période (trop ancien) → exclu des provisions', (
      tester,
    ) async {
      final payments = [
        _makePayment(
          id: 'old',
          periodStart: DateTime(2015, 1, 1),
          periodEnd: DateTime(2015, 1, 31),
          chargesAmountCents: 999900,
        ),
      ];

      await tester.pumpWidget(_buildDialog(payments: payments));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(MoneyFormat.formatEurosFromCents(999900)),
        findsNothing,
      );
    });
  });

  group('ChargeRegularizationDialog — calcul du solde en direct', () {
    testWidgets(
      'saisie de dépenses réelles > provisions → libellé "à réclamer au '
      'locataire"',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        final payments = [
          _makePayment(
            id: 'p1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            chargesAmountCents: 120000,
          ),
        ];

        await tester.pumpWidget(_buildDialog(payments: payments));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_actual_expenses')),
          '1300,00',
        );
        await tester.pumpAndSettle();

        expect(find.text('à réclamer au locataire'), findsOneWidget);
      },
    );

    testWidgets(
      'saisie de dépenses réelles < provisions → libellé "à rembourser au '
      'locataire"',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        final payments = [
          _makePayment(
            id: 'p1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            chargesAmountCents: 120000,
          ),
        ];

        await tester.pumpWidget(_buildDialog(payments: payments));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_actual_expenses')),
          '900,00',
        );
        await tester.pumpAndSettle();

        expect(find.text('à rembourser au locataire'), findsOneWidget);
      },
    );

    testWidgets(
      'saisie de dépenses réelles == provisions → libellé "aucun solde"',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        final payments = [
          _makePayment(
            id: 'p1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            chargesAmountCents: 120000,
          ),
        ];

        await tester.pumpWidget(_buildDialog(payments: payments));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_actual_expenses')),
          '1200,00',
        );
        await tester.pumpAndSettle();

        expect(find.text('aucun solde'), findsOneWidget);
      },
    );
  });

  group('ChargeRegularizationDialog — actions', () {
    testWidgets('bouton Annuler ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildDialog(payments: const []));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Régularisation annuelle des charges'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('btn_charge_regularization_cancel')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Régularisation annuelle des charges'), findsNothing);
    });

    testWidgets('bouton "Générer et partager" présent', (tester) async {
      await tester.pumpWidget(_buildDialog(payments: const []));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('btn_charge_regularization_generate')),
        findsOneWidget,
      );
    });
  });

  group('ChargeRegularizationDialog — correctif review : bouton désactivé '
      'pendant le chargement des paiements', () {
    testWidgets('asyncPayments en loading (jamais résolu) → bouton "Générer et '
        'partager" désactivé', (tester) async {
      await tester.pumpWidget(
        _buildDialog(
          payments: const [],
          paymentRepository: const _FakePaymentRepo.pending(),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      // Un seul pump (pas pumpAndSettle) : `listForLease` ne résout
      // jamais dans ce test, l'UI doit donc rester bloquée sur l'état
      // loading du dialog — pumpAndSettle boucherait indéfiniment sur un
      // Future qui ne se termine jamais.
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('btn_charge_regularization_generate')),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            'Générer avant que les paiements soient chargés produirait '
            'un avis avec provisions=0 (bug review FEAT-029).',
      );
    });

    testWidgets(
      'paiements chargés (data) → bouton "Générer et partager" activé',
      (tester) async {
        await tester.pumpWidget(_buildDialog(payments: const []));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('btn_charge_regularization_generate')),
        );
        expect(button.onPressed, isNotNull);
      },
    );
  });

  group('ChargeRegularizationDialog — correctif review : garde période '
      'début <= fin', () {
    testWidgets(
      'période par défaut (12 derniers mois glissants, valide) → bouton '
      '"Générer et partager" activé, aucun message d\'erreur',
      (tester) async {
        await tester.pumpWidget(_buildDialog(payments: const []));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('btn_charge_regularization_generate')),
        );
        expect(button.onPressed, isNotNull);
        expect(
          find.text('La date de fin doit être postérieure à la date de début'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'le picker de fin de période s\'ouvre bien avec une borne minimale '
      'contrainte au lendemain du début (showDatePicker ne lève pas)',
      (tester) async {
        await tester.pumpWidget(_buildDialog(payments: const []));
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        final endPickerFinder = find.ancestor(
          of: find.text('Fin de période'),
          matching: find.byType(InputDecorator),
        );
        expect(endPickerFinder, findsOneWidget);

        await tester.tap(endPickerFinder);
        await tester.pumpAndSettle();

        // Le showDatePicker doit s'être ouvert sans lever d'assertion
        // Flutter (initialDate/firstDate/lastDate cohérents) — régression
        // possible si `minDate` dépasse `date` sans le clamp défensif
        // ajouté dans ChargeRegularizationPeriodPicker.
        expect(find.byType(CalendarDatePicker), findsOneWidget);

        // Ferme le picker sans sélectionner (annule) pour ne pas modifier
        // l'état du dialog parent.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });

  group('ChargeRegularizationDialog — FEAT-041c : pré-remplissage depuis '
      'les dépenses récupérables', () {
    testWidgets(
      'dépenses récupérables couvrant la période → champ "Dépenses réelles" '
      'pré-rempli avec leur somme',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        final expenses = [
          _makeExpense(
            id: 'exp-1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            amountCents: 45000,
          ),
          _makeExpense(
            id: 'exp-2',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            amountCents: 15000,
          ),
        ];

        await tester.pumpWidget(
          _buildDialog(payments: const [], expenses: expenses),
        );
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextFormField>(
          find.byKey(const Key('field_actual_expenses')),
        );
        expect(field.controller?.text, MoneyFormat.centsToInput(60000));
        expect(
          find.text('Pré-rempli depuis 2 dépenses — modifiable.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('dépense non-récupérable uniquement → EXCLUE, champ reste vide '
        '(pré-remplissage à 0 == valeur initiale, aucune écriture, comme V1)', (
      tester,
    ) async {
      final now = DateTime.now();
      final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
      final expenses = [
        _makeExpense(
          id: 'exp-non-recoverable',
          periodStart: periodStart,
          periodEnd: DateTime(now.year, now.month, now.day),
          amountCents: 99900,
          category: ExpenseCategory.nonRecoverable,
        ),
      ];

      await tester.pumpWidget(
        _buildDialog(payments: const [], expenses: expenses),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('field_actual_expenses')),
      );
      expect(field.controller?.text, isEmpty);
      expect(
        find.byKey(const Key('text_charge_regularization_prefill_hint')),
        findsNothing,
      );
    });

    testWidgets(
      'saisie manuelle après pré-remplissage → conservée malgré le stream '
      'de dépenses (garde _userEditedExpenses)',
      (tester) async {
        final now = DateTime.now();
        final periodStart = DateTime(now.year - 1, now.month, now.day + 1);
        final expenses = [
          _makeExpense(
            id: 'exp-1',
            periodStart: periodStart,
            periodEnd: DateTime(now.year, now.month, now.day),
            amountCents: 60000,
          ),
        ];

        await tester.pumpWidget(
          _buildDialog(payments: const [], expenses: expenses),
        );
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        // Pré-rempli à 600,00 € au départ.
        var field = tester.widget<TextFormField>(
          find.byKey(const Key('field_actual_expenses')),
        );
        expect(field.controller?.text, MoneyFormat.centsToInput(60000));

        // L'utilisateur écrase la valeur pré-remplie.
        await tester.enterText(
          find.byKey(const Key('field_actual_expenses')),
          '250,00',
        );
        await tester.pumpAndSettle();

        field = tester.widget<TextFormField>(
          find.byKey(const Key('field_actual_expenses')),
        );
        expect(field.controller?.text, '250,00');

        // Un nouveau build (ex. changement de période) ne doit PAS écraser
        // la saisie manuelle avec le pré-remplissage automatique.
        await tester.tap(
          find.ancestor(
            of: find.text('Début de période'),
            matching: find.byType(InputDecorator),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10)); // Ferme sans sélectionner.
        await tester.pumpAndSettle();

        field = tester.widget<TextFormField>(
          find.byKey(const Key('field_actual_expenses')),
        );
        expect(
          field.controller?.text,
          '250,00',
          reason:
              'Une fois éditée manuellement, la saisie ne doit plus être '
              'écrasée par le pré-remplissage automatique.',
        );
      },
    );

    testWidgets('0 dépense récupérable → NON-RÉGRESSION : champ reste à 0,00, '
        'comportement V1 strictement inchangé', (tester) async {
      await tester.pumpWidget(_buildDialog(payments: const []));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('field_actual_expenses')),
      );
      expect(field.controller?.text, isEmpty);
      expect(
        find.byKey(const Key('text_charge_regularization_prefill_hint')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('tile_charge_regularization_expenses_detail')),
        findsNothing,
      );

      // La saisie manuelle à 0 reste fonctionnellement identique à avant
      // FEAT-041c : le solde se calcule normalement.
      await tester.enterText(
        find.byKey(const Key('field_actual_expenses')),
        '0',
      );
      await tester.pumpAndSettle();
      expect(find.text('aucun solde'), findsOneWidget);
    });
  });
}

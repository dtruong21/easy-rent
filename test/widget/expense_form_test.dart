/// Tests widget de [ExpenseForm].
///
/// Couvre (cf. plan `docs/plans/FEAT-041-depenses.md` § i) :
/// - verrouillage dur de la catégorie sur une nature verrouillée
///   (`property_tax`/`insurance_pno`/`management_fees`) ;
/// - avertissement explicite si le bailleur bascule une nature ajustable
///   vers `recoverable` alors que ce n'est pas le défaut ;
/// - validation montant/date/période (validateAll retourne false si champs
///   obligatoires vides).
library;

import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:easyrent/features/expenses/presentation/expense_form.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildExpenseForm({
  required TextEditingController amountCtrl,
  List<Lease> leases = const [],
  String? initialLeaseId,
  DateTime? initialExpenseDate,
  ExpenseNature? initialNature,
  ExpenseCategory? initialCategory,
  bool initialCategoryOverridden = false,
  DateTime? initialPeriodStart,
  DateTime? initialPeriodEnd,
  String? initialNotes,
  String? initialDocumentId,
  bool enabled = true,
  GlobalKey<ExpenseFormWidgetState>? formKey,
}) {
  final gk = GlobalKey<FormState>();
  final wk = formKey ?? GlobalKey<ExpenseFormWidgetState>();
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpenseForm(
            key: wk,
            formKey: gk,
            amountController: amountCtrl,
            leases: leases,
            propertyId: 'property-1',
            initialLeaseId: initialLeaseId,
            initialExpenseDate: initialExpenseDate,
            initialNature: initialNature,
            initialCategory: initialCategory,
            initialCategoryOverridden: initialCategoryOverridden,
            initialPeriodStart: initialPeriodStart,
            initialPeriodEnd: initialPeriodEnd,
            initialNotes: initialNotes,
            initialDocumentId: initialDocumentId,
            enabled: enabled,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExpenseForm — champs présents', () {
    testWidgets('champ montant présent', (tester) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_amount')), findsOneWidget);
      amountCtrl.dispose();
    });

    testWidgets('champ nature présent', (tester) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_nature')), findsOneWidget);
      amountCtrl.dispose();
    });

    testWidgets('champ date de dépense présent', (tester) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_expense_date')), findsOneWidget);
      amountCtrl.dispose();
    });

    testWidgets('champ bail (dropdown optionnel) présent', (tester) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_lease_id')), findsOneWidget);
      amountCtrl.dispose();
    });

    testWidgets('champ notes présent', (tester) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_notes')), findsOneWidget);
      amountCtrl.dispose();
    });

    testWidgets('aucun champ catégorie tant que la nature n\'est pas choisie', (
      tester,
    ) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
      expect(find.byKey(const Key('field_category')), findsNothing);
      expect(find.byKey(const Key('category_locked_banner')), findsNothing);
      amountCtrl.dispose();
    });
  });

  group('ExpenseForm — verrouillage dur sur nature verrouillée', () {
    testWidgets(
      'nature "Taxe foncière" → bandeau verrouillé, pas de dropdown catégorie',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.propertyTax,
          ),
        );
        expect(find.byKey(const Key('category_locked_banner')), findsOneWidget);
        expect(find.byKey(const Key('field_category')), findsNothing);
        expect(find.textContaining('Non récupérable'), findsOneWidget);
        amountCtrl.dispose();
      },
    );

    testWidgets(
      'nature "Assurance PNO" → bandeau verrouillé, pas de dropdown catégorie',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.insurancePno,
          ),
        );
        expect(find.byKey(const Key('category_locked_banner')), findsOneWidget);
        expect(find.byKey(const Key('field_category')), findsNothing);
        amountCtrl.dispose();
      },
    );

    testWidgets(
      'nature "Honoraires de gestion" → bandeau verrouillé, pas de dropdown '
      'catégorie',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.managementFees,
          ),
        );
        expect(find.byKey(const Key('category_locked_banner')), findsOneWidget);
        expect(find.byKey(const Key('field_category')), findsNothing);
        amountCtrl.dispose();
      },
    );

    testWidgets(
      'sélection de "Taxe foncière" via le picker verrouille dynamiquement '
      'la catégorie',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));

        await tester.tap(find.byKey(const Key('field_nature')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ExpenseNature.propertyTax.label).last);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('category_locked_banner')), findsOneWidget);
        expect(find.byKey(const Key('field_category')), findsNothing);
        amountCtrl.dispose();
      },
    );
  });

  group('ExpenseForm — nature ajustable : dropdown catégorie visible', () {
    testWidgets(
      'nature "Charges de copropriété" → dropdown catégorie visible',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.condoCharges,
          ),
        );
        expect(find.byKey(const Key('field_category')), findsOneWidget);
        expect(find.byKey(const Key('category_locked_banner')), findsNothing);
        amountCtrl.dispose();
      },
    );

    testWidgets('pas d\'avertissement si la catégorie == défaut de la nature', (
      tester,
    ) async {
      final amountCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildExpenseForm(
          amountCtrl: amountCtrl,
          initialNature: ExpenseNature.condoCharges,
        ),
      );
      // Défaut condo_charges == recoverable → pas d'avertissement.
      expect(find.byKey(const Key('category_override_warning')), findsNothing);
      amountCtrl.dispose();
    });
  });

  group(
    'ExpenseForm — avertissement override (nature ajustable → recoverable)',
    () {
      testWidgets(
        'bascule "Travaux" (non_recoverable par défaut) vers recoverable → '
        'avertissement affiché',
        (tester) async {
          final amountCtrl = TextEditingController();
          await tester.pumpWidget(
            _buildExpenseForm(
              amountCtrl: amountCtrl,
              initialNature: ExpenseNature.works,
            ),
          );
          expect(
            find.byKey(const Key('category_override_warning')),
            findsNothing,
          );

          await tester.tap(find.byKey(const Key('field_category')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(ExpenseCategory.recoverable.label).last);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('category_override_warning')),
            findsOneWidget,
          );
          amountCtrl.dispose();
        },
      );

      testWidgets(
        'currentCategoryOverridden reflète le forçage vers recoverable',
        (tester) async {
          final amountCtrl = TextEditingController();
          final wk = GlobalKey<ExpenseFormWidgetState>();
          await tester.pumpWidget(
            _buildExpenseForm(
              amountCtrl: amountCtrl,
              initialNature: ExpenseNature.works,
              formKey: wk,
            ),
          );

          await tester.tap(find.byKey(const Key('field_category')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(ExpenseCategory.recoverable.label).last);
          await tester.pumpAndSettle();

          expect(wk.currentState?.currentCategoryOverridden, isTrue);
          expect(wk.currentState?.currentCategory, ExpenseCategory.recoverable);
          amountCtrl.dispose();
        },
      );

      testWidgets(
        'changer de nature réinitialise l\'override manuel précédent',
        (tester) async {
          final amountCtrl = TextEditingController();
          final wk = GlobalKey<ExpenseFormWidgetState>();
          await tester.pumpWidget(
            _buildExpenseForm(
              amountCtrl: amountCtrl,
              initialNature: ExpenseNature.works,
              formKey: wk,
            ),
          );

          await tester.tap(find.byKey(const Key('field_category')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(ExpenseCategory.recoverable.label).last);
          await tester.pumpAndSettle();
          expect(wk.currentState?.currentCategoryOverridden, isTrue);

          // Nouvelle nature → override réinitialisé.
          await tester.tap(find.byKey(const Key('field_nature')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(ExpenseNature.repairMaintenance.label).last,
          );
          await tester.pumpAndSettle();

          expect(wk.currentState?.currentCategoryOverridden, isFalse);
          expect(
            wk.currentState?.currentCategory,
            ExpenseNature.repairMaintenance.defaultCategory,
          );
          amountCtrl.dispose();
        },
      );
    },
  );

  group('ExpenseForm — validateAll (montant/date/période)', () {
    testWidgets('validateAll retourne false si tous les champs sont vides', (
      tester,
    ) async {
      final amountCtrl = TextEditingController();
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(amountCtrl: amountCtrl, formKey: wk),
      );
      final result = wk.currentState?.validateAll() ?? true;
      await tester.pump();
      expect(result, isFalse);
      amountCtrl.dispose();
    });

    testWidgets(
      'validateAll retourne false si la nature n\'est pas sélectionnée',
      (tester) async {
        final amountCtrl = TextEditingController(text: '450,00');
        final wk = GlobalKey<ExpenseFormWidgetState>();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialExpenseDate: DateTime(2025, 3, 15),
            formKey: wk,
          ),
        );
        final result = wk.currentState?.validateAll() ?? true;
        await tester.pump();
        expect(result, isFalse);
        amountCtrl.dispose();
      },
    );

    testWidgets('validateAll retourne false pour une dépense récupérable sans '
        'période de rattachement', (tester) async {
      final amountCtrl = TextEditingController(text: '450,00');
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(
          amountCtrl: amountCtrl,
          initialNature: ExpenseNature.condoCharges,
          initialExpenseDate: DateTime(2025, 3, 15),
          formKey: wk,
        ),
      );
      // condoCharges → recoverable par défaut, mais période non saisie
      // explicitement ici (le picker dérive la période uniquement au tap).
      // On force les champs de période à null pour ce test.
      final result = wk.currentState?.validateAll() ?? true;
      await tester.pump();
      // La période a été dérivée automatiquement par le constructeur
      // uniquement via les pickers interactifs — initState ne la dérive
      // pas. On s'attend donc à un échec de validation ici.
      expect(result, isFalse);
      amountCtrl.dispose();
    });

    testWidgets(
      'validateAll retourne true pour une dépense complète (non récupérable, '
      'période optionnelle)',
      (tester) async {
        final amountCtrl = TextEditingController(text: '450,00');
        final wk = GlobalKey<ExpenseFormWidgetState>();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.propertyTax,
            initialExpenseDate: DateTime(2025, 3, 15),
            formKey: wk,
          ),
        );
        final result = wk.currentState?.validateAll() ?? false;
        await tester.pump();
        expect(result, isTrue);
        amountCtrl.dispose();
      },
    );

    testWidgets(
      'validateAll retourne true pour une dépense récupérable avec période '
      'complète',
      (tester) async {
        final amountCtrl = TextEditingController(text: '450,00');
        final wk = GlobalKey<ExpenseFormWidgetState>();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialNature: ExpenseNature.condoCharges,
            initialExpenseDate: DateTime(2025, 3, 15),
            initialPeriodStart: DateTime(2025, 1, 1),
            initialPeriodEnd: DateTime(2025, 12, 31),
            formKey: wk,
          ),
        );
        final result = wk.currentState?.validateAll() ?? false;
        await tester.pump();
        expect(result, isTrue);
        amountCtrl.dispose();
      },
    );

    testWidgets('montant à 0 → validateAll retourne false', (tester) async {
      final amountCtrl = TextEditingController(text: '0');
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(
          amountCtrl: amountCtrl,
          initialNature: ExpenseNature.propertyTax,
          initialExpenseDate: DateTime(2025, 3, 15),
          formKey: wk,
        ),
      );
      final result = wk.currentState?.validateAll() ?? true;
      await tester.pump();
      expect(result, isFalse);
      amountCtrl.dispose();
    });
  });

  group('ExpenseForm — getters courants', () {
    testWidgets('currentNature reflète la sélection', (tester) async {
      final amountCtrl = TextEditingController();
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(
          amountCtrl: amountCtrl,
          initialNature: ExpenseNature.works,
          formKey: wk,
        ),
      );
      expect(wk.currentState?.currentNature, ExpenseNature.works);
      amountCtrl.dispose();
    });

    testWidgets('currentLeaseId == null par défaut (aucun bail)', (
      tester,
    ) async {
      final amountCtrl = TextEditingController();
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(amountCtrl: amountCtrl, formKey: wk),
      );
      expect(wk.currentState?.currentLeaseId, isNull);
      amountCtrl.dispose();
    });

    testWidgets('currentNotes retourne le texte saisi (trim)', (tester) async {
      final amountCtrl = TextEditingController();
      final wk = GlobalKey<ExpenseFormWidgetState>();
      await tester.pumpWidget(
        _buildExpenseForm(
          amountCtrl: amountCtrl,
          initialNotes: '  décompte syndic  ',
          formKey: wk,
        ),
      );
      expect(wk.currentState?.currentNotes, 'décompte syndic');
      amountCtrl.dispose();
    });
  });

  group('ExpenseForm — justificatif existant transmis au champ (correctif '
      'review FEAT-041, finding 6)', () {
    testWidgets(
      'initialDocumentId fourni (édition) → ExpenseReceiptField affiche '
      '"justificatif déjà attaché"',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(
          _buildExpenseForm(
            amountCtrl: amountCtrl,
            initialDocumentId: 'doc-existing-1',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('text_expense_receipt_existing')),
          findsOneWidget,
        );
        amountCtrl.dispose();
      },
    );

    testWidgets(
      'initialDocumentId == null (création) → bouton "Joindre" classique',
      (tester) async {
        final amountCtrl = TextEditingController();
        await tester.pumpWidget(_buildExpenseForm(amountCtrl: amountCtrl));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_pick_expense_receipt')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('text_expense_receipt_existing')),
          findsNothing,
        );
        amountCtrl.dispose();
      },
    );
  });
}

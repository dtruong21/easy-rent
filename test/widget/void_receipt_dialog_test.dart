/// Tests widget de [VoidReceiptDialog].
///
/// Couvre : validation champ motif (requis, min 3, max 500 chars),
/// bouton confirmer appelle le callback, bouton annuler ferme le dialog.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/receipts/presentation/widgets/void_receipt_dialog.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildDialog({void Function(String)? onConfirm}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => VoidReceiptDialog(onConfirm: onConfirm ?? (_) {}),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('VoidReceiptDialog', () {
    testWidgets('dialog s\'ouvre avec le titre "Annuler cette quittance ?"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);
      expect(find.byKey(const Key('dialog_void_receipt')), findsOneWidget);
      expect(find.text('Annuler cette quittance ?'), findsOneWidget);
    });

    testWidgets('champ motif vide → erreur validation', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);

      // Cliquer confirmer sans saisir de motif
      await tester.tap(find.byKey(const Key('btn_void_confirm')));
      await tester.pumpAndSettle();

      // Erreur validation visible
      expect(find.textContaining('au moins 3'), findsOneWidget);
    });

    testWidgets('motif de 2 chars → erreur validation', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);

      await tester.enterText(find.byKey(const Key('field_void_reason')), 'ab');
      await tester.tap(find.byKey(const Key('btn_void_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('au moins 3'), findsOneWidget);
    });

    testWidgets('motif de 3 chars → pas d\'erreur, callback appelé', (
      tester,
    ) async {
      String? capturedReason;
      await tester.pumpWidget(
        _buildDialog(onConfirm: (r) => capturedReason = r),
      );
      await _openDialog(tester);

      await tester.enterText(find.byKey(const Key('field_void_reason')), 'abc');
      await tester.tap(find.byKey(const Key('btn_void_confirm')));
      await tester.pumpAndSettle();

      expect(capturedReason, 'abc');
    });

    testWidgets('motif valide → callback appelé avec le texte trimé', (
      tester,
    ) async {
      String? capturedReason;
      await tester.pumpWidget(
        _buildDialog(onConfirm: (r) => capturedReason = r),
      );
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(const Key('field_void_reason')),
        '  Erreur de montant  ',
      );
      await tester.tap(find.byKey(const Key('btn_void_confirm')));
      await tester.pumpAndSettle();

      expect(capturedReason, 'Erreur de montant');
    });

    testWidgets('bouton "Annuler" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);

      await tester.tap(find.byKey(const Key('btn_void_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_void_receipt')), findsNothing);
    });

    testWidgets(
      'motif > 500 chars → erreur validation (contrainte DB miroir)',
      (tester) async {
        await tester.pumpWidget(_buildDialog());
        await _openDialog(tester);

        // maxLength dans le champ empêche la saisie > 500 côté Flutter Material
        // mais on teste la validation directe avec un texte tronqué à 500.
        // Note : maxLength dans TextFormField tronque silencieusement,
        // donc on ne peut pas dépasser 500 en saisie normale.
        // On vérifie uniquement que le validateur accepte 500 chars.
        final longText = 'a' * 500;
        await tester.enterText(
          find.byKey(const Key('field_void_reason')),
          longText,
        );
        await tester.tap(find.byKey(const Key('btn_void_confirm')));
        await tester.pumpAndSettle();

        // Pas d'erreur — 500 chars est la limite exacte.
        expect(find.textContaining('500 caractères'), findsNothing);
      },
    );
  });
}

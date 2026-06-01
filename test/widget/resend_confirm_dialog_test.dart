/// Tests widget de [ConfirmResendDialog].
///
/// Couvre :
/// - dialog s'ouvre avec titre et corps corrects
/// - bouton Annuler ferme sans appeler onConfirm
/// - bouton Renvoyer appelle onConfirm et ferme le dialog
library;

import 'package:easyrent/features/receipts/presentation/widgets/confirm_resend_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildDialog({
  required VoidCallback onConfirm,
  DateTime? previousSentAt,
  String previousMaskedEmail = 'j***@example.com',
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          key: const Key('open_dialog'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ConfirmResendDialog(
              previousSentAt: previousSentAt ?? DateTime(2026, 5, 1),
              previousMaskedEmail: previousMaskedEmail,
              onConfirm: onConfirm,
            ),
          ),
          child: const Text('Ouvrir'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConfirmResendDialog — affichage', () {
    testWidgets('dialog contient le titre correct', (tester) async {
      await tester.pumpWidget(_buildDialog(onConfirm: () {}));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsOneWidget);
      expect(find.textContaining('Renvoyer cette quittance'), findsOneWidget);
    });

    testWidgets('dialog contient la date formatée FR', (tester) async {
      await tester.pumpWidget(
        _buildDialog(onConfirm: () {}, previousSentAt: DateTime(2026, 5, 15)),
      );
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      // Date formatée en FR : "15/05/2026".
      expect(find.textContaining('15/05/2026'), findsOneWidget);
    });

    testWidgets('dialog contient l\'email masqué', (tester) async {
      await tester.pumpWidget(
        _buildDialog(onConfirm: () {}, previousMaskedEmail: 'l***@test.fr'),
      );
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.textContaining('l***@test.fr'), findsOneWidget);
    });

    testWidgets('boutons Annuler et Renvoyer présents', (tester) async {
      await tester.pumpWidget(_buildDialog(onConfirm: () {}));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_resend_cancel')), findsOneWidget);
      expect(find.byKey(const Key('btn_resend_confirm')), findsOneWidget);
    });
  });

  group('ConfirmResendDialog — interactions', () {
    testWidgets('clic Annuler → dialog fermé, onConfirm NON appelé', (
      tester,
    ) async {
      var confirmCalled = false;
      await tester.pumpWidget(
        _buildDialog(onConfirm: () => confirmCalled = true),
      );
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_resend_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsNothing);
      expect(confirmCalled, false);
    });

    testWidgets('clic Renvoyer → onConfirm appelé, dialog fermé', (
      tester,
    ) async {
      var confirmCalled = false;
      await tester.pumpWidget(
        _buildDialog(onConfirm: () => confirmCalled = true),
      );
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_resend_confirm')));
      await tester.pumpAndSettle();

      expect(confirmCalled, true);
      expect(find.byKey(const Key('dialog_confirm_resend')), findsNothing);
    });
  });
}

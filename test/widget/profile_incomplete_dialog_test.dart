/// Tests widget de [ProfileIncompleteDialog].
///
/// Couvre : bouton "Compléter mon profil" navigue vers /profile,
/// liste des champs manquants affichée, bouton "Plus tard" ferme.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/receipts/presentation/widgets/profile_incomplete_dialog.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildDialog({List<String> missing = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ProfileIncompleteDialog(missing: missing),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, _) =>
            const Scaffold(body: Text('Profile Page Destination')),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
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
  group('ProfileIncompleteDialog', () {
    testWidgets('dialog s\'ouvre avec le titre "Profil incomplet"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);
      expect(
        find.byKey(const Key('dialog_profile_incomplete')),
        findsOneWidget,
      );
      expect(find.text('Profil incomplet'), findsOneWidget);
    });

    testWidgets('message légal visible', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);
      expect(find.textContaining('loi du 6 juillet 1989'), findsOneWidget);
    });

    testWidgets('affiche les champs manquants', (tester) async {
      await tester.pumpWidget(_buildDialog(missing: ['full_name', 'address']));
      await _openDialog(tester);
      expect(find.text('• Nom complet'), findsOneWidget);
      expect(find.text('• Adresse postale'), findsOneWidget);
    });

    testWidgets('bouton "Plus tard" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);

      await tester.tap(find.byKey(const Key('btn_profile_incomplete_later')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_profile_incomplete')), findsNothing);
    });

    testWidgets('bouton "Compléter mon profil" navigue vers /profile', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog());
      await _openDialog(tester);

      await tester.tap(find.byKey(const Key('btn_profile_incomplete_go')));
      await tester.pumpAndSettle();

      expect(find.text('Profile Page Destination'), findsOneWidget);
    });

    testWidgets('sans champs manquants → pas de section "Champs manquants"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(missing: []));
      await _openDialog(tester);
      expect(find.text('Champs manquants :'), findsNothing);
    });
  });
}

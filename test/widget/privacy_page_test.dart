/// Tests widget pour [PrivacyPage] — vérification des sections RGPD.
///
/// Vérifie la présence des sections obligatoires et l'absence de l'adresse
/// email placeholder support@easyrent.fr (mitigation sec #7).
library;

import 'package:easyrent/features/privacy/presentation/privacy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap(Widget child) => MaterialApp.router(
  routerConfig: GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => child)],
  ),
  theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
);

/// Retourne tous les textes affichés dans l'arbre widget (y compris hors écran).
String _allText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in tester.allWidgets) {
    if (element is Text && element.data != null) {
      buffer.write(element.data);
    }
  }
  return buffer.toString();
}

void main() {
  group('PrivacyPage — sections RGPD', () {
    testWidgets('affiche le titre principal', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPage()));
      await tester.pumpAndSettle();
      expect(find.text('Politique de confidentialité'), findsWidgets);
    });

    testWidgets('contient les 9 titres de sections', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPage()));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, contains('1. Responsable du traitement'));
      expect(text, contains('2. Données collectées'));
      expect(text, contains('3. Base légale (RGPD art. 6.1.b)'));
      expect(text, contains('4. Sous-traitants et transferts'));
      expect(text, contains('5. Durée de conservation'));
      expect(text, contains('6. Sécurité'));
      expect(text, contains('7. Cookies et traceurs'));
      expect(text, contains('8. Vos droits (RGPD art. 15–21)'));
      expect(text, contains('9. Mise à jour de cette politique'));
    });

    testWidgets(
      'ne contient pas l\'adresse email placeholder support@easyrent.fr',
      (tester) async {
        await tester.pumpWidget(_wrap(const PrivacyPage()));
        await tester.pumpAndSettle();

        final text = _allText(tester);
        // L'adresse email placeholder a été remplacée par une formulation RGPD propre.
        expect(text, isNot(contains('support@easyrent.fr')));
      },
    );

    testWidgets('mentionne la CNIL', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPage()));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, contains('CNIL'));
    });

    testWidgets('mentionne la loi du 6 juillet 1989', (tester) async {
      await tester.pumpWidget(_wrap(const PrivacyPage()));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      expect(text, contains('6 juillet 1989'));
    });

    testWidgets('mentionne Firebase/Google comme sous-traitant (RGPD)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const PrivacyPage()));
      await tester.pumpAndSettle();

      final text = _allText(tester);
      // Post FEAT-019 : la stack data est passée de Supabase à Firebase.
      // L'obligation RGPD reste : informer l'utilisateur du sous-traitant.
      expect(text, contains('Firebase'));
      expect(text, contains('Google'));
      // Vérifie aussi qu'on ne mentionne plus Supabase (résidu RGPD).
      expect(text, isNot(contains('Supabase')));
    });
  });
}

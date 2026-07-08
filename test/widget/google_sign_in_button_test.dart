import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/presentation/widgets/google_sign_in_button.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('GoogleSignInButton', () {
    testWidgets('rend le label "Continuer avec Google" par défaut', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(GoogleSignInButton(onPressed: () {}, isLoading: false)),
      );

      expect(find.text('Continuer avec Google'), findsOneWidget);
    });

    testWidgets('isLoading=true remplace le label par un indicateur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(GoogleSignInButton(onPressed: () {}, isLoading: true)),
      );

      expect(find.text('Continuer avec Google'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('onPressed=null désactive le bouton', (tester) async {
      await tester.pumpWidget(
        _wrap(GoogleSignInButton(onPressed: null, isLoading: false)),
      );

      final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('tap déclenche le callback quand actif', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          GoogleSignInButton(onPressed: () => tapped = true, isLoading: false),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('le logo Google (CustomPaint) est présent', (tester) async {
      await tester.pumpWidget(
        _wrap(GoogleSignInButton(onPressed: () {}, isLoading: false)),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}

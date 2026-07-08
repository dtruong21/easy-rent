/// Tests widget pour [ViewModeToggle].
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/view_mode.dart';
import 'package:easyrent/core/ui/cards/view_mode_provider.dart';
import 'package:easyrent/core/ui/cards/view_mode_storage.dart';
import 'package:easyrent/core/ui/cards/view_mode_toggle.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({required double screenWidth}) {
  return ProviderScope(
    overrides: [viewModeStorageProvider.overrideWithValue(ViewModeStorage())],
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: Size(screenWidth, 800)),
          child: const ViewModeToggle(pageKey: 'test'),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ViewModeToggle — masquage mobile', () {
    testWidgets(
      'sur mobile (< 600px) → SizedBox.shrink visible (rien affiché)',
      (tester) async {
        await tester.pumpWidget(_wrap(screenWidth: 400));
        await tester.pump();
        expect(find.byType(SegmentedButton<ViewMode>), findsNothing);
      },
    );

    testWidgets('sur mobile 599px → aucun segment rendu', (tester) async {
      await tester.pumpWidget(_wrap(screenWidth: 599));
      await tester.pump();
      expect(find.text('Cartes'), findsNothing);
      expect(find.text('Tableau'), findsNothing);
    });
  });

  group('ViewModeToggle — desktop', () {
    testWidgets('sur desktop (>= 600px) → SegmentedButton rendu', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(screenWidth: 1024));
      await tester.pump();
      expect(find.byType(SegmentedButton<ViewMode>), findsOneWidget);
    });

    testWidgets('segments "Cartes" et "Tableau" présents', (tester) async {
      await tester.pumpWidget(_wrap(screenWidth: 1024));
      await tester.pump();
      expect(find.text('Cartes'), findsOneWidget);
      expect(find.text('Tableau'), findsOneWidget);
    });

    testWidgets('état initial = Cartes sélectionné', (tester) async {
      await tester.pumpWidget(_wrap(screenWidth: 1024));
      await tester.pump();
      final segButton = tester.widget<SegmentedButton<ViewMode>>(
        find.byType(SegmentedButton<ViewMode>),
      );
      expect(segButton.selected, contains(ViewMode.card));
    });

    testWidgets('tap Tableau → provider passe à table', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            viewModeStorageProvider.overrideWithValue(ViewModeStorage()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(size: Size(1024, 800)),
                child: Consumer(
                  builder: (context, ref, child) {
                    capturedRef = ref;
                    return const ViewModeToggle(pageKey: 'test_page');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Tableau'));
      await tester.pump();

      final mode = capturedRef.read(viewModeProvider('test_page'));
      expect(mode, ViewMode.table);
    });
  });

  group('ViewModeToggle — tablette (600px)', () {
    testWidgets('sur tablette 600px → toggle visible', (tester) async {
      await tester.pumpWidget(_wrap(screenWidth: 600));
      await tester.pump();
      expect(find.byType(SegmentedButton<ViewMode>), findsOneWidget);
    });
  });
}

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/widgets/archive_confirm_dialog.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers : construit le dialog avec les textes pour chaque entité.
// ---------------------------------------------------------------------------

Widget _buildPropertyDialog({
  required bool hasActiveLease,
  VoidCallback? onConfirm,
}) {
  return MaterialApp(
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Builder(
        builder: (context) => ArchiveConfirmDialog(
          title: 'Archiver ce bien ?',
          entityLabel: 'Appart Test',
          standardMessage:
              'Voulez-vous archiver "Appart Test" ? '
              "Le bien n'apparaîtra plus dans votre liste. "
              'Les baux liés seront conservés.',
          activeLeaseMessage:
              'Ce bien a un bail actif. Êtes-vous sûr de vouloir archiver '
              '"Appart Test" ? Les baux actifs liés seront conservés '
              "mais le bien n'apparaîtra plus dans votre liste.",
          hasActiveLease: hasActiveLease,
          onConfirm: onConfirm ?? () {},
        ),
      ),
    ),
  );
}

Widget _buildTenantDialog({
  required bool hasActiveLease,
  VoidCallback? onConfirm,
}) {
  return MaterialApp(
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Builder(
        builder: (context) => ArchiveConfirmDialog(
          title: 'Archiver ce locataire ?',
          entityLabel: 'Jean Dupont',
          standardMessage:
              'Voulez-vous archiver "Jean Dupont" ? '
              "Le locataire n'apparaîtra plus dans votre liste. "
              'Les baux liés seront conservés.',
          activeLeaseMessage:
              'Ce locataire a un bail actif. Êtes-vous sûr de vouloir archiver '
              '"Jean Dupont" ? Les baux actifs liés seront conservés '
              "mais le locataire n'apparaîtra plus dans votre liste.",
          hasActiveLease: hasActiveLease,
          onConfirm: onConfirm ?? () {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — entité "bien" (rétro-compatibilité)
// ---------------------------------------------------------------------------

void main() {
  group('ArchiveConfirmDialog — bien immobilier', () {
    testWidgets('titre "Archiver ce bien ?" présent (sans bail)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: false));
      expect(find.text('Archiver ce bien ?'), findsOneWidget);
    });

    testWidgets('titre "Archiver ce bien ?" présent (avec bail actif)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: true));
      expect(find.text('Archiver ce bien ?'), findsOneWidget);
    });

    testWidgets('sans bail actif — message standard affiché', (tester) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: false));
      expect(find.textContaining('Appart Test'), findsOneWidget);
      expect(find.textContaining("n'apparaîtra plus"), findsOneWidget);
    });

    testWidgets('sans bail actif — pas de mention "bail actif"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: false));
      expect(find.textContaining('bail actif'), findsNothing);
    });

    testWidgets('avec bail actif — message renforcé affiché', (tester) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: true));
      expect(find.textContaining('bail actif'), findsOneWidget);
    });

    testWidgets('avec bail actif — avertissement "Êtes-vous sûr" visible', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: true));
      expect(find.textContaining('sûr'), findsOneWidget);
    });

    testWidgets('boutons "Annuler" et "Archiver" présents', (tester) async {
      await tester.pumpWidget(_buildPropertyDialog(hasActiveLease: false));
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Archiver'), findsOneWidget);
    });

    testWidgets('tap "Archiver" appelle onConfirm', (tester) async {
      bool confirmed = false;
      await tester.pumpWidget(
        _buildPropertyDialog(
          hasActiveLease: false,
          onConfirm: () => confirmed = true,
        ),
      );
      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('tap "Archiver" (bail actif) appelle onConfirm', (
      tester,
    ) async {
      bool confirmed = false;
      await tester.pumpWidget(
        _buildPropertyDialog(
          hasActiveLease: true,
          onConfirm: () => confirmed = true,
        ),
      );
      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — entité "locataire" (FEAT-004)
  // ---------------------------------------------------------------------------

  group('ArchiveConfirmDialog — locataire', () {
    testWidgets('titre "Archiver ce locataire ?" présent (sans bail)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: false));
      expect(find.text('Archiver ce locataire ?'), findsOneWidget);
    });

    testWidgets('titre "Archiver ce locataire ?" présent (avec bail actif)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: true));
      expect(find.text('Archiver ce locataire ?'), findsOneWidget);
    });

    testWidgets('sans bail actif — message standard affiché', (tester) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: false));
      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.textContaining("n'apparaîtra plus"), findsOneWidget);
    });

    testWidgets('sans bail actif — pas de mention "bail actif"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: false));
      expect(find.textContaining('bail actif'), findsNothing);
    });

    testWidgets('avec bail actif — mention "locataire a un bail actif"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: true));
      expect(find.textContaining('bail actif'), findsOneWidget);
    });

    testWidgets('avec bail actif — avertissement "Êtes-vous sûr" visible', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: true));
      expect(find.textContaining('sûr'), findsOneWidget);
    });

    testWidgets('boutons "Annuler" et "Archiver" présents', (tester) async {
      await tester.pumpWidget(_buildTenantDialog(hasActiveLease: false));
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Archiver'), findsOneWidget);
    });

    testWidgets('tap "Archiver" appelle onConfirm', (tester) async {
      bool confirmed = false;
      await tester.pumpWidget(
        _buildTenantDialog(
          hasActiveLease: false,
          onConfirm: () => confirmed = true,
        ),
      );
      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('tap "Archiver" (bail actif) appelle onConfirm', (
      tester,
    ) async {
      bool confirmed = false;
      await tester.pumpWidget(
        _buildTenantDialog(
          hasActiveLease: true,
          onConfirm: () => confirmed = true,
        ),
      );
      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });
  });
}

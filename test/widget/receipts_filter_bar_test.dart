/// Tests widget de [ReceiptsFilterBar].
///
/// Couvre : puces de filtre (toutes largeurs), sélection → provider,
/// toggle ViewMode (desktop uniquement, masqué sur mobile).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/cards/view_mode.dart';
import 'package:easyrent/core/ui/cards/view_mode_provider.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/receipts/application/receipts_filter_provider.dart';
import 'package:easyrent/features/receipts/domain/receipt_status_filter.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipts_filter_bar.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

const _leaseId = 'lease-test';

Widget _buildDesktop(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            const Scaffold(body: ReceiptsFilterBar(leaseId: _leaseId)),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(900, 700)),
      child: MaterialApp.router(
        routerConfig: router,
        theme: _appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
      ),
    ),
  );
}

Widget _buildMobile(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            const Scaffold(body: ReceiptsFilterBar(leaseId: _leaseId)),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(375, 667)),
      child: MaterialApp.router(
        routerConfig: router,
        theme: _appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ReceiptsFilterBar', () {
    testWidgets('desktop — puces de filtre visibles (4)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      for (final f in ReceiptStatusFilter.values) {
        expect(find.byKey(Key('filter_chip_$f')), findsOneWidget);
      }
      expect(find.textContaining('Toutes'), findsOneWidget);
      expect(find.textContaining('Envoyées'), findsOneWidget);
      expect(find.textContaining('Payées'), findsOneWidget);
      expect(find.textContaining('Annulées'), findsOneWidget);
    });

    testWidgets(
      'desktop — tap puce "Annulées" → provider = ReceiptStatusFilter.voided',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        expect(
          container.read(receiptStatusFilterProvider(_leaseId)),
          ReceiptStatusFilter.all,
        );

        final chip = find.byKey(
          Key('filter_chip_${ReceiptStatusFilter.voided}'),
        );
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();

        expect(
          container.read(receiptStatusFilterProvider(_leaseId)),
          ReceiptStatusFilter.voided,
        );
      },
    );

    testWidgets('mobile — puces de filtre visibles', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      for (final f in ReceiptStatusFilter.values) {
        expect(find.byKey(Key('filter_chip_$f')), findsOneWidget);
      }
    });

    testWidgets('desktop — toggle ViewMode visible (Cartes / Chronologie)', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(find.text('Cartes'), findsOneWidget);
      // Le mode `table` ouvre la timeline : jamais « Tableau » ici.
      expect(find.text('Chronologie'), findsOneWidget);
      expect(find.text('Tableau'), findsNothing);
    });

    testWidgets('mobile — toggle ViewMode masqué', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(find.text('Cartes'), findsNothing);
      expect(find.text('Chronologie'), findsNothing);
    });

    testWidgets('desktop — clic "Cartes" → viewMode = ViewMode.card', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cartes'));
      await tester.pumpAndSettle();

      expect(
        container.read(viewModeProvider('receipts:$_leaseId')),
        ViewMode.card,
      );
    });
  });
}

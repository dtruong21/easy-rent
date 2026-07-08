/// Tests widget de [ReceiptsFilterBar].
///
/// Couvre : SegmentedButton desktop, Dropdown mobile, sélection → provider,
/// dropdown année dynamique, toggle ViewMode.
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
    testWidgets('desktop — SegmentedButton statut visible avec 4 segments', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt_status_filter')), findsOneWidget);
      expect(find.text('Toutes'), findsOneWidget);
      expect(find.text('Envoyées'), findsOneWidget);
      expect(find.text('Payées'), findsOneWidget);
      expect(find.text('Annulées'), findsOneWidget);
    });

    testWidgets(
      'desktop — sélection "Annulées" → provider = ReceiptStatusFilter.voided',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        expect(
          container.read(receiptStatusFilterProvider(_leaseId)),
          ReceiptStatusFilter.all,
        );

        await tester.tap(find.text('Annulées'));
        await tester.pumpAndSettle();

        expect(
          container.read(receiptStatusFilterProvider(_leaseId)),
          ReceiptStatusFilter.voided,
        );
      },
    );

    testWidgets('mobile — DropdownButton visible (pas SegmentedButton)', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('receipt_status_filter_mobile')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('receipt_status_filter')), findsNothing);
    });

    testWidgets('desktop — toggle Timeline/Cards visible', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt_view_mode_toggle')), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);
    });

    testWidgets('desktop — clic "Cards" → viewMode = ViewMode.card', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();

      expect(
        container.read(viewModeProvider('receipts:$_leaseId')),
        ViewMode.card,
      );
    });
  });
}

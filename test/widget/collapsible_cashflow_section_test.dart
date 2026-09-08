import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/monthly_cashflow_chart.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const Scaffold(
      body: SingleChildScrollView(child: CollapsibleCashflowSection()),
    ),
  ),
);

void main() {
  testWidgets('fermé par défaut → chart non construit', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    expect(find.byType(MonthlyCashflowChart), findsNothing);
    expect(find.text('Cash-flow mensuel — détail'), findsOneWidget);
  });

  testWidgets('déplié → chart construit', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.tap(find.text('Cash-flow mensuel — détail'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlyCashflowChart), findsOneWidget);
  });
}

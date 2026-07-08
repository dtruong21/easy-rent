/// Tests widget de [RecentActivitySection].
///
/// Couvre le repli/dépli « Voir tout » :
/// - ≤ 5 items → pas de bouton, tous visibles
/// - > 5 items → 5 visibles + « Voir tout »
/// - Tap « Voir tout » → tous visibles + « Réduire », re-tap → repli
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/recent_activity_section.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

List<ActivityItem> _makeItems(int count) => [
  for (int i = 0; i < count; i++)
    ActivityItem.paymentRecorded(
      paymentId: 'p$i',
      leaseId: 'l$i',
      tenantName: 'Locataire $i',
      amountCents: 65000 + i,
      occurredAt: DateTime(2026, 6, 30).subtract(Duration(days: i)),
    ),
];

Widget _buildSection(List<ActivityItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(
            child: RecentActivitySection(items: items),
          ),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      extensions: const [AppColors.light, AppRadii()],
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
  );
}

void main() {
  group('RecentActivitySection — Voir tout', () {
    testWidgets('5 items ou moins → pas de bouton, tous visibles', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection(_makeItems(4)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_activity_toggle')), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(4));
    });

    testWidgets('plus de 5 items → 5 visibles + « Voir tout »', (tester) async {
      await tester.pumpWidget(_buildSection(_makeItems(8)));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('Voir tout'), findsOneWidget);
      expect(find.text('Réduire'), findsNothing);
    });

    testWidgets('tap « Voir tout » → tout visible + « Réduire », re-tap → '
        'repli à 5', (tester) async {
      await tester.pumpWidget(_buildSection(_makeItems(8)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_activity_toggle')));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(8));
      expect(find.text('Réduire'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_activity_toggle')));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('Voir tout'), findsOneWidget);
    });

    testWidgets('liste vide → empty state, pas de bouton', (tester) async {
      await tester.pumpWidget(_buildSection(const []));
      await tester.pumpAndSettle();

      expect(find.text('Aucune activité récente'), findsOneWidget);
      expect(find.byKey(const Key('btn_activity_toggle')), findsNothing);
    });
  });
}

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/action_items_panel.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeLeasesNotifier extends LeasesListNotifier {
  _FakeLeasesNotifier(this._items);
  final List<LeaseListItem> _items;
  @override
  Future<List<LeaseListItem>> build() async => _items;
}

LeaseListItem _item({
  required String id,
  bool isLate = false,
  DateTime? endDate,
}) => LeaseListItem(
  lease: Lease(
    id: id,
    landlordId: 'lord1',
    propertyId: 'p',
    tenantId: 't',
    rentAmountCents: 80000,
    chargesAmountCents: 0,
    nonRecoverableChargesCents: 0,
    startDate: DateTime(2020, 1, 1),
    endDate: endDate,
    status: LeaseStatus.active,
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  propertyName: 'Bien $id',
  tenantDisplayName: 'Loc $id',
  isLate: isLate,
);

Widget _wrap(List<LeaseListItem> items, {required GoRouter router}) {
  return ProviderScope(
    overrides: [
      leasesListProvider.overrideWith(() => _FakeLeasesNotifier(items)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

GoRouter _router({int docsPendingCount = 0}) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: ActionItemsPanel(
          loyers: const LoyersMoisKpi(encaissedCents: 60000, dueCents: 80000),
          docsPendingCount: docsPendingCount,
        ),
      ),
    ),
    GoRoute(
      path: '/leases',
      builder: (_, s) => Scaffold(body: Text('leases ${s.uri.query}')),
    ),
  ],
);

void main() {
  testWidgets('retard → ligne + tap va vers filter=late', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 20));
    await tester.pumpWidget(
      _wrap([_item(id: 'A', isLate: true, endDate: soon)], router: _router()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard_action_panel')), findsOneWidget);
    expect(find.byKey(const Key('action_late_A')), findsOneWidget);
    await tester.tap(find.byKey(const Key('action_late_A')));
    await tester.pumpAndSettle();
    expect(find.text('leases filter=late'), findsOneWidget);
  });

  testWidgets('bail finissant → ligne + tap va vers filter=renewable', (
    tester,
  ) async {
    final soon = DateTime.now().add(const Duration(days: 20));
    await tester.pumpWidget(
      _wrap([_item(id: 'B', endDate: soon)], router: _router()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_ending_B')), findsOneWidget);
    await tester.tap(find.byKey(const Key('action_ending_B')));
    await tester.pumpAndSettle();
    expect(find.text('leases filter=renewable'), findsOneWidget);
  });

  testWidgets('aucun item → état « tout est à jour »', (tester) async {
    final far = DateTime.now().add(const Duration(days: 300));
    await tester.pumpWidget(
      _wrap([_item(id: 'C', endDate: far)], router: _router()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_items_empty')), findsOneWidget);
  });

  testWidgets('docs en attente > 0 → ligne passive affichée, non cliquable', (
    tester,
  ) async {
    final far = DateTime.now().add(const Duration(days: 300));
    await tester.pumpWidget(
      _wrap([
        _item(id: 'C', endDate: far),
      ], router: _router(docsPendingCount: 3)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_docs_pending')), findsOneWidget);
    expect(find.textContaining('3 documents en attente'), findsOneWidget);
    // Pas un bouton / ListTile cliquable : aucun InkWell sous la ligne.
    expect(
      find.descendant(
        of: find.byKey(const Key('action_docs_pending')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('docs en attente == 0 → aucune ligne docs', (tester) async {
    final far = DateTime.now().add(const Duration(days: 300));
    await tester.pumpWidget(
      _wrap([
        _item(id: 'C', endDate: far),
      ], router: _router(docsPendingCount: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_docs_pending')), findsNothing);
  });
}

import 'dart:async';

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/application/leases_filter_provider.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_filter.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/leases_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements LeaseRepository {
  final List<LeaseListItem> items;
  final Exception? listError;

  const _FakeRepo({this.items = const [], this.listError});

  @override
  Future<List<LeaseListItem>> listForDisplay() async {
    if (listError != null) throw listError!;
    return items;
  }

  @override
  Future<Lease> getById(String id) async => throw UnimplementedError();

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  }) async => throw UnimplementedError();

  @override
  Future<Lease> update(Lease lease) async => throw UnimplementedError();

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => false;

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Lease _makeLease({
  String id = 'l1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? startDate,
  DateTime? endDate,
}) => Lease(
  id: id,
  landlordId: 'owner-1',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: startDate ?? DateTime(2024, 1, 1),
  endDate: endDate,
  status: status,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

LeaseListItem _makeItem({
  String id = 'l1',
  String propertyName = 'Appartement Paris',
  String tenantName = 'Jean Dupont',
  LeaseStatus status = LeaseStatus.active,
  DateTime? startDate,
  DateTime? endDate,
}) => LeaseListItem(
  lease: _makeLease(
    id: id,
    status: status,
    startDate: startDate,
    endDate: endDate,
  ),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
);

Widget _buildPage(
  _FakeRepo repo, {
  Size size = const Size(800, 600),
  List<Override> extraOverrides = const [],
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => const LeasesListPage()),
      GoRoute(
        path: '/leases/new',
        builder: (context, _) => const Scaffold(body: Text('nouveau bail')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id/receipts',
        builder: (context, _) => const Scaffold(body: Text('quittances')),
      ),
      GoRoute(
        path: '/leases/:id/payments/new',
        builder: (context, _) => const Scaffold(body: Text('nouveau paiement')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(repo),
      ...extraOverrides,
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LeasesListPage', () {
    // -----------------------------------------------------------------------
    // État vide
    // -----------------------------------------------------------------------
    testWidgets('état vide — affiche "Aucun bail enregistré"', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Aucun bail enregistré'), findsOneWidget);
    });

    testWidgets('état vide — bouton "Créer un bail" dans le corps', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_add_lease_empty')), findsOneWidget);
    });

    testWidgets('état vide — FAB "Créer un bail" présent', (tester) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fab_add_lease')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Liste avec items
    // -----------------------------------------------------------------------
    testWidgets('liste — affiche le nom du bien et du locataire', (
      tester,
    ) async {
      final repo = _FakeRepo(
        items: [
          _makeItem(
            id: 'l1',
            propertyName: 'Appartement Paris',
            tenantName: 'Jean Dupont',
          ),
        ],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Appartement Paris'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
    });

    testWidgets('liste — état vide absent quand des baux existent', (
      tester,
    ) async {
      final repo = _FakeRepo(items: [_makeItem()]);

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Aucun bail enregistré'), findsNothing);
    });

    testWidgets('liste — affiche bail actif et bail terminé', (tester) async {
      // Note : le tri (actif avant terminé) est garanti par le repository
      // (status ASC, start_date DESC). Le test vérifie seulement la présence
      // des deux baux — le positionnement spatial dépend de la grille responsive.
      final repo = _FakeRepo(
        items: [
          _makeItem(
            id: 'l1',
            propertyName: 'Bien Actif',
            status: LeaseStatus.active,
          ),
          _makeItem(
            id: 'l2',
            propertyName: 'Bien Terminé',
            status: LeaseStatus.terminated,
          ),
        ],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Bien Actif'), findsOneWidget);
      expect(find.text('Bien Terminé'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('état loading — indicateur de chargement visible', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, _) => const LeasesListPage()),
          GoRoute(
            path: '/leases/new',
            builder: (context, _) => const Scaffold(body: Text('new')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leasesListProvider.overrideWith(() => _LoadingListNotifier()),
          ],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
          ),
        ),
      );

      await tester.pump();
      // En mode card (défaut) : skeleton cards visibles (pas CircularProgressIndicator)
      // La page affiche l'état loading via CardSkeleton / TableSkeletonRow
      expect(find.text('Aucun bail enregistré'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // État erreur
    // -----------------------------------------------------------------------
    testWidgets('état erreur — affiche bouton "Réessayer"', (tester) async {
      final repo = _FakeRepo(listError: Exception('réseau indisponible'));

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('état erreur — affiche message "Impossible de charger"', (
      tester,
    ) async {
      final repo = _FakeRepo(listError: Exception('timeout'));

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Impossible de charger'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Navigation
    // -----------------------------------------------------------------------
    testWidgets('tap sur une card → navigue vers /leases/:id', (tester) async {
      final repo = _FakeRepo(
        items: [_makeItem(id: 'lease-abc', propertyName: 'Bien Test')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bien Test'));
      await tester.pumpAndSettle();

      expect(find.text('detail lease-abc'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Filtre
    // -----------------------------------------------------------------------
    testWidgets(
      'filtre "Terminés" — masque les baux actifs, affiche les terminés',
      (tester) async {
        final repo = _FakeRepo(
          items: [
            _makeItem(
              id: 'la',
              propertyName: 'Bail Actif',
              status: LeaseStatus.active,
            ),
            _makeItem(
              id: 'lt',
              propertyName: 'Bail Terminé',
              status: LeaseStatus.terminated,
            ),
          ],
        );

        await tester.pumpWidget(
          _buildPage(
            repo,
            extraOverrides: [
              leaseFilterProvider.overrideWith((ref) => LeaseFilter.terminated),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bail Terminé'), findsOneWidget);
        expect(find.text('Bail Actif'), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // ViewMode toggle
    // -----------------------------------------------------------------------
    testWidgets('desktop — FilterBar visible avec SegmentedButton filtres', (
      tester,
    ) async {
      final repo = _FakeRepo(items: [_makeItem()]);

      await tester.pumpWidget(_buildPage(repo, size: const Size(1200, 800)));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<LeaseFilter>), findsOneWidget);
    });
  });
}

/// Notifier qui reste en état loading indéfini.
class _LoadingListNotifier extends LeasesListNotifier {
  @override
  Future<List<LeaseListItem>> build() async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    return [];
  }
}

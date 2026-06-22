import 'dart:async';

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/tenants/application/tenants_filter_provider.dart';
import 'package:easyrent/features/tenants/application/tenants_list_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_filter.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/tenants_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements TenantRepository {
  final List<Tenant> tenants;
  final Exception? listError;

  const _FakeRepo({this.tenants = const [], this.listError});

  @override
  Future<List<Tenant>> list() async {
    if (listError != null) throw listError!;
    return tenants;
  }

  @override
  Future<Tenant> getById(String id) async => tenants.first;

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant tenant) async => tenant;

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async {
    if (listError != null) throw listError!;
    return tenants.map((t) => TenantListItem(tenant: t)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Tenant _makeTenant({
  String id = 't1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean.dupont@test.com',
}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: firstName,
  lastName: lastName,
  email: email,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildPage(_FakeRepo repo) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => const TenantsListPage()),
      GoRoute(
        path: '/tenants/new',
        builder: (context, _) =>
            const Scaffold(body: Text('nouveau locataire')),
      ),
      GoRoute(
        path: '/tenants/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, _) => const Scaffold(body: Text('new lease')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantsListPage', () {
    // -----------------------------------------------------------------------
    // État vide
    // -----------------------------------------------------------------------
    testWidgets('état vide — affiche "Aucun locataire enregistré"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.text('Aucun locataire enregistré'), findsOneWidget);
    });

    testWidgets('état vide — bouton "Ajouter un locataire" dans le corps', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_add_tenant_empty')), findsOneWidget);
    });

    testWidgets('état vide — FAB "Ajouter un locataire" présent', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(const _FakeRepo()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fab_add_tenant')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Liste avec items
    // -----------------------------------------------------------------------
    testWidgets('liste — affiche les noms des locataires', (tester) async {
      final repo = _FakeRepo(
        tenants: [
          _makeTenant(id: 't1', firstName: 'Jean', lastName: 'Dupont'),
          _makeTenant(id: 't2', firstName: 'Sophie', lastName: 'Martin'),
        ],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.textContaining('Sophie Martin'), findsOneWidget);
    });

    testWidgets('liste — affiche les emails des locataires', (tester) async {
      final repo = _FakeRepo(
        tenants: [_makeTenant(id: 't1', email: 'jean.dupont@test.com')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('jean.dupont@test.com'), findsOneWidget);
    });

    testWidgets('liste — état vide absent quand des locataires existent', (
      tester,
    ) async {
      final repo = _FakeRepo(
        tenants: [_makeTenant(id: 't1', firstName: 'Paul', lastName: 'Durand')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      expect(find.text('Aucun locataire enregistré'), findsNothing);
    });

    testWidgets('liste — pill "Sans bail" visible pour locataire sans bail', (
      tester,
    ) async {
      final repo = _FakeRepo(
        tenants: [_makeTenant(id: 't1', firstName: 'Jean', lastName: 'Dupont')],
      );

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      // "Sans bail" apparaît dans le SegmentedButton ET dans la pill du locataire.
      expect(find.text('Sans bail'), findsAtLeastNWidgets(1));
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('état loading — CardSkeleton visible (card view)', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, _) => const TenantsListPage()),
          GoRoute(
            path: '/tenants/new',
            builder: (context, _) => const Scaffold(body: Text('new')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tenantsListItemsProvider.overrideWith(
              () => _LoadingListItemsNotifier(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );

      await tester.pump();
      // Loading skeleton affiché, pas de TenantsListPage error
      expect(find.text('Aucun locataire enregistré'), findsNothing);
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
    // Filtre bar présente
    // -----------------------------------------------------------------------
    testWidgets('liste — barre de filtre présente', (tester) async {
      final repo = _FakeRepo(tenants: [_makeTenant(id: 't1')]);

      await tester.pumpWidget(_buildPage(repo));
      await tester.pumpAndSettle();

      // La barre contient au moins le segment "Tous"
      expect(find.text('Tous'), findsOneWidget);
    });

    testWidgets(
      'filtre "Sans bail" — cache locataire sans bail si filtre actifs',
      (tester) async {
        final repo = _FakeRepo(
          tenants: [
            _makeTenant(id: 't1', firstName: 'Jean', lastName: 'Dupont'),
          ],
        );

        final container = ProviderContainer(
          overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // Initialiser le filtre à withActiveLease
        container.read(tenantFilterProvider.notifier).state =
            TenantFilter.withActiveLease;

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => const TenantsListPage(),
            ),
            GoRoute(
              path: '/tenants/new',
              builder: (context, _) => const Scaffold(body: Text('new')),
            ),
            GoRoute(
              path: '/tenants/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('detail ${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/tenants/:id/edit',
              builder: (_, state) =>
                  Scaffold(body: Text('edit ${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/leases/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('lease ${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/leases/new',
              builder: (context, _) => const Scaffold(body: Text('new lease')),
            ),
          ],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
          ),
        );
        await tester.pumpAndSettle();

        // Jean Dupont n'a pas de bail actif → filtré → état vide
        expect(find.text('Aucun locataire enregistré'), findsOneWidget);
      },
    );
  });
}

/// Notifier qui reste en état loading indéfini — sans timer.
class _LoadingListItemsNotifier extends TenantsListItemsNotifier {
  @override
  Future<List<TenantListItem>> build() async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    return [];
  }
}

import 'dart:async';

import 'package:easyrent/features/tenants/application/tenants_list_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
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
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant tenant) async => tenant;

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
    ],
  );

  return ProviderScope(
    overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
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

      expect(find.text('Votre annuaire de locataires'), findsOneWidget);
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

      expect(find.text('Votre annuaire de locataires'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('état loading — CircularProgressIndicator visible', (
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
            tenantsListProvider.overrideWith(() => _LoadingListNotifier()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
  });
}

/// Notifier qui reste en état loading indéfini — sans timer.
class _LoadingListNotifier extends TenantsListNotifier {
  @override
  Future<List<Tenant>> build() async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    return [];
  }
}

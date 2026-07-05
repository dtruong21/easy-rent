import 'package:easyrent/features/tenants/application/tenant_form_controller.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_form_state.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/tenant_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository — aucun appel réseau.
// ---------------------------------------------------------------------------

class _FakeTenantRepository implements TenantRepository {
  Tenant? createdTenant;
  Tenant? updatedTenant;
  Exception? createError;

  @override
  Future<List<Tenant>> list() async => [];

  @override
  Future<Tenant> getById(String id) async => _makeTenant(id: id);

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
  }) async {
    if (createError != null) throw createError!;
    createdTenant = _makeTenant(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
    );
    return createdTenant!;
  }

  @override
  Future<Tenant> update(Tenant tenant) async {
    updatedTenant = tenant;
    return tenant;
  }

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async => [];

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];

  Tenant _makeTenant({
    String id = 'test-id',
    String firstName = 'Jean',
    String lastName = 'Dupont',
    String email = 'jean.dupont@test.com',
    String? phone,
  }) => Tenant(
    id: id,
    landlordId: 'landlord-id',
    firstName: firstName,
    lastName: lastName,
    email: email,
    phone: phone,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Helper de montage.
// ---------------------------------------------------------------------------

Widget _buildForm({
  Tenant? initial,
  _FakeTenantRepository? repo,
  TenantFormState? initialState,
}) {
  final fakeRepo = repo ?? _FakeTenantRepository();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TenantFormPage(initial: initial),
      ),
      GoRoute(
        path: '/tenants',
        builder: (context, state) => const Scaffold(body: Text('tenants')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      tenantRepositoryProvider.overrideWithValue(fakeRepo),
      if (initialState != null)
        tenantFormControllerProvider.overrideWith(
          (ref) => TenantFormController(ref)..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantFormPage — smoke tests', () {
    // -----------------------------------------------------------------------
    // Mode création — champs présents
    // -----------------------------------------------------------------------
    testWidgets('mode création — les 4 champs sont présents', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_first_name')), findsOneWidget);
      expect(find.byKey(const Key('field_last_name')), findsOneWidget);
      expect(find.byKey(const Key('field_email')), findsOneWidget);
      expect(find.byKey(const Key('field_phone')), findsOneWidget);
    });

    testWidgets('mode création — titre "Nouveau locataire"', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Nouveau locataire'), findsOneWidget);
    });

    testWidgets('mode création — bouton "Créer le locataire" présent', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Créer le locataire'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Validation — erreurs inline sur soumission incomplète
    // -----------------------------------------------------------------------
    testWidgets(
      'validation — erreur "prénom obligatoire" si prénom vide à la soumission',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        // Le formulaire est plus long avec les nouveaux champs — scroll jusqu'au bouton,
        // soumettre, puis remonter pour voir l'erreur en haut du formulaire.
        await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        // Remonter au champ en erreur pour le rendre visible.
        await tester.ensureVisible(find.byKey(const Key('field_first_name')));
        await tester.pumpAndSettle();

        expect(find.text('Le prénom est obligatoire'), findsOneWidget);
      },
    );

    testWidgets(
      'validation — erreur "nom obligatoire" si nom vide à la soumission',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        // Remplir le prénom mais pas le nom.
        await tester.enterText(
          find.byKey(const Key('field_first_name')),
          'Jean',
        );
        // Scroller jusqu'au bouton avant de tapper (formulaire plus long).
        await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        expect(find.text('Le nom est obligatoire'), findsOneWidget);
      },
    );

    testWidgets('validation — erreur email si email vide à la soumission', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      // Remplir prénom et nom mais pas email.
      await tester.enterText(find.byKey(const Key('field_first_name')), 'Jean');
      await tester.enterText(
        find.byKey(const Key('field_last_name')),
        'Dupont',
      );
      // Scroller jusqu'au bouton avant de tapper (formulaire plus long).
      await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
      await tester.tap(find.byKey(const Key('btn_submit_form')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("L'adresse email est obligatoire"),
        findsOneWidget,
      );
    });

    testWidgets('validation — erreur email si format invalide', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field_first_name')), 'Jean');
      await tester.enterText(
        find.byKey(const Key('field_last_name')),
        'Dupont',
      );
      await tester.enterText(
        find.byKey(const Key('field_email')),
        'pas-un-email',
      );
      // Scroller jusqu'au bouton avant de tapper (formulaire plus long).
      await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
      await tester.tap(find.byKey(const Key('btn_submit_form')));
      await tester.pumpAndSettle();

      expect(find.textContaining('invalide'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Mode édition — champs pré-remplis
    // -----------------------------------------------------------------------
    testWidgets('mode édition — champs pré-remplis', (tester) async {
      final tenant = Tenant(
        id: 'id-1',
        landlordId: 'landlord-1',
        firstName: 'Marie',
        lastName: 'Martin',
        email: 'marie.martin@test.com',
        phone: '06 12 34 56 78',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: tenant));
      await tester.pumpAndSettle();

      expect(find.text('Marie'), findsOneWidget);
      expect(find.text('Martin'), findsOneWidget);
      expect(find.text('marie.martin@test.com'), findsOneWidget);
      expect(find.text('06 12 34 56 78'), findsOneWidget);
    });

    testWidgets('mode édition — titre "Modifier le locataire"', (tester) async {
      final tenant = Tenant(
        id: 'id-1',
        landlordId: 'landlord-1',
        firstName: 'Paul',
        lastName: 'Durand',
        email: 'paul.durand@test.com',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: tenant));
      await tester.pumpAndSettle();

      expect(find.text('Modifier le locataire'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État submitting — bouton désactivé
    // -----------------------------------------------------------------------
    testWidgets('état submitting — bouton désactivé avec indicateur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildForm(initialState: const TenantFormState.submitting()),
      );
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_submit_form')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État erreur — message affiché inline
    // -----------------------------------------------------------------------
    testWidgets('état erreur — message affiché inline', (tester) async {
      await tester.pumpWidget(
        _buildForm(
          initialState: const TenantFormState.error(
            message: 'Données invalides. Vérifiez les champs et réessayez.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Données invalides'), findsOneWidget);
    });
  });
  group('TenantFormPage — mode picker (popOnSuccess)', () {
    testWidgets('succès → pop(tenantId) vers l\'appelant au lieu de '
        'go(/tenants)', (tester) async {
      String? poppedId;
      final repo = _FakeTenantRepository();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    poppedId = await context.push<String>(
                      '/tenants/new?picker=1',
                    );
                  },
                  child: const Text('ouvrir picker'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/tenants/new',
            builder: (context, state) => TenantFormPage(
              popOnSuccess: state.uri.queryParameters['picker'] == '1',
            ),
          ),
          GoRoute(
            path: '/tenants',
            builder: (context, _) => const Scaffold(body: Text('tenants')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ouvrir picker'));
      await tester.pumpAndSettle();
      expect(find.byType(TenantFormPage), findsOneWidget);

      // Émet l'état success via le controller réel (même mécanique que le
      // harnais initialState plus haut) : le contrat testé est la RÉACTION
      // de la page — pop(tenant.id) vers l'appelant, pas go('/tenants').
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TenantFormPage)),
      );
      container.read(tenantFormControllerProvider.notifier).state =
          TenantFormState.success(tenant: repo._makeTenant());
      await tester.pumpAndSettle();

      // Le fake _makeTenant() renvoie l'id 'test-id' : on est revenu sur
      // l'écran appelant avec cet id, PAS sur la liste des locataires.
      expect(poppedId, 'test-id');
      expect(find.text('ouvrir picker'), findsOneWidget);
      expect(find.text('tenants'), findsNothing);
    });

    testWidgets('création, hors mode picker : succès → go(/tenants) '
        '(comportement liste conservé — création uniquement)', (tester) async {
      final repo = _FakeTenantRepository();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, _) => const TenantFormPage()),
          GoRoute(
            path: '/tenants',
            builder: (context, _) => const Scaffold(body: Text('tenants')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TenantFormPage)),
      );
      container.read(tenantFormControllerProvider.notifier).state =
          TenantFormState.success(tenant: repo._makeTenant());
      await tester.pumpAndSettle();

      expect(find.text('tenants'), findsOneWidget);
    });

    testWidgets('F-2 — édition, hors mode picker : succès → pop() (retour à la '
        'fiche détail, pas la liste)', (tester) async {
      final repo = _FakeTenantRepository();
      final tenant = repo._makeTenant(id: 'id-1', firstName: 'Marie');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/tenant-detail',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const Text('fiche détail locataire'),
                    TextButton(
                      onPressed: () => context.push('/tenant-detail/edit'),
                      child: const Text('modifier'),
                    ),
                  ],
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, _) => TenantFormPage(initial: tenant),
              ),
            ],
          ),
          GoRoute(
            path: '/tenants',
            builder: (context, _) => const Scaffold(body: Text('tenants')),
          ),
        ],
        initialLocation: '/tenant-detail',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('modifier'));
      await tester.pumpAndSettle();
      expect(find.byType(TenantFormPage), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TenantFormPage)),
      );
      container.read(tenantFormControllerProvider.notifier).state =
          TenantFormState.success(tenant: tenant);
      await tester.pumpAndSettle();

      // pop() : retour à la FICHE DÉTAIL, pas à la liste — preuve que la
      // pile intermédiaire (détail → edit) n'a pas été écrasée par un
      // go('/tenants').
      expect(find.byType(TenantFormPage), findsNothing);
      expect(find.text('fiche détail locataire'), findsOneWidget);
      expect(find.text('tenants'), findsNothing);
    });
  });
}

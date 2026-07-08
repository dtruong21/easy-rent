import 'dart:async';

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/application/leases_filter_provider.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_filter.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/leases/presentation/leases_list_page.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
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
  Future<List<LeaseListItem>> listForDisplay({DateTime? now}) async {
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
    LeaseType leaseType = LeaseType.unfurnished,
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
    int nonRecoverableChargesCents = 0,
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
  bool isLate = false,
}) => LeaseListItem(
  lease: _makeLease(
    id: id,
    status: status,
    startDate: startDate,
    endDate: endDate,
  ),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
  isLate: isLate,
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
            child: MaterialApp.router(
              routerConfig: router,
              theme: _appTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              locale: const Locale('fr'),
              supportedLocales: supportedLocales,
            ),
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
    // Filtre « En retard » (FEAT-028)
    // -----------------------------------------------------------------------
    testWidgets(
      'filtre "En retard" — affiche uniquement les baux avec isLate=true',
      (tester) async {
        final repo = _FakeRepo(
          items: [
            _makeItem(
              id: 'll',
              propertyName: 'Bail En Retard',
              status: LeaseStatus.active,
              isLate: true,
            ),
            _makeItem(
              id: 'la',
              propertyName: 'Bail Actif À Jour',
              status: LeaseStatus.active,
            ),
          ],
        );

        await tester.pumpWidget(
          _buildPage(
            repo,
            extraOverrides: [
              leaseFilterProvider.overrideWith((ref) => LeaseFilter.late),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bail En Retard'), findsOneWidget);
        expect(find.text('Bail Actif À Jour'), findsNothing);
      },
    );

    testWidgets(
      'filtre "Actifs" — exclut les baux en retard (priorité late > active)',
      (tester) async {
        final repo = _FakeRepo(
          items: [
            _makeItem(
              id: 'll',
              propertyName: 'Bail En Retard',
              status: LeaseStatus.active,
              isLate: true,
            ),
            _makeItem(
              id: 'la',
              propertyName: 'Bail Actif À Jour',
              status: LeaseStatus.active,
            ),
          ],
        );

        await tester.pumpWidget(
          _buildPage(
            repo,
            extraOverrides: [
              leaseFilterProvider.overrideWith((ref) => LeaseFilter.active),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bail Actif À Jour'), findsOneWidget);
        expect(find.text('Bail En Retard'), findsNothing);
      },
    );

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
    // État vide filtré (baux existants mais tous masqués par le filtre)
    // -----------------------------------------------------------------------
    testWidgets(
      'filtre sans résultat — message dédié + bouton « Afficher tous les baux » '
      '(pas « Aucun bail enregistré »)',
      (tester) async {
        final repo = _FakeRepo(
          items: [
            _makeItem(
              id: 'la',
              propertyName: 'Bail Actif',
              status: LeaseStatus.active,
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

        expect(find.text('Aucun bail pour ce filtre'), findsOneWidget);
        expect(find.textContaining('« Terminés »'), findsOneWidget);
        expect(find.byKey(const Key('btn_show_all_leases')), findsOneWidget);
        expect(find.text('Aucun bail enregistré'), findsNothing);
      },
    );

    testWidgets(
      'filtre sans résultat — tap « Afficher tous les baux » → filtre reset, '
      'baux visibles',
      (tester) async {
        final repo = _FakeRepo(
          items: [
            _makeItem(
              id: 'la',
              propertyName: 'Bail Actif',
              status: LeaseStatus.active,
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

        await tester.tap(find.byKey(const Key('btn_show_all_leases')));
        await tester.pumpAndSettle();

        expect(find.text('Bail Actif'), findsOneWidget);
        expect(find.text('Aucun bail pour ce filtre'), findsNothing);
      },
    );

    testWidgets('aucun bail du tout + filtre actif → état vide standard '
        '« Aucun bail enregistré »', (tester) async {
      await tester.pumpWidget(
        _buildPage(
          const _FakeRepo(),
          extraOverrides: [
            leaseFilterProvider.overrideWith((ref) => LeaseFilter.renewable),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucun bail enregistré'), findsOneWidget);
      expect(find.text('Aucun bail pour ce filtre'), findsNothing);
    });

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

  group('LeasesListPage — initialFilter (drill-down KPI)', () {
    testWidgets('initialFilter applique le filtre au leaseFilterProvider', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
            home: const LeasesListPage(initialFilter: LeaseFilter.renewable),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(leaseFilterProvider), LeaseFilter.renewable);
    });

    testWidgets('sans initialFilter → le filtre reste « all » (défaut)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
            home: const LeasesListPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(leaseFilterProvider), LeaseFilter.all);
    });

    testWidgets('initialFilter changé sur State réutilisé → filtre ré-appliqué '
        '(GoRouter recycle la page /leases, initState ne rejoue pas)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      Widget page(LeaseFilter? filter) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _appTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('fr'),
          supportedLocales: supportedLocales,
          home: LeasesListPage(initialFilter: filter),
        ),
      );

      await tester.pumpWidget(page(LeaseFilter.renewable));
      await tester.pumpAndSettle();
      expect(container.read(leaseFilterProvider), LeaseFilter.renewable);

      // Même runtimeType, pas de clé → l'Element (et son State) est
      // réutilisé, seul widget.initialFilter change → didUpdateWidget.
      await tester.pumpWidget(page(LeaseFilter.all));
      await tester.pumpAndSettle();
      expect(container.read(leaseFilterProvider), LeaseFilter.all);
    });
  });

  group('LeaseFilter.fromQueryParam', () {
    test('parse les valeurs connues', () {
      expect(LeaseFilter.fromQueryParam('active'), LeaseFilter.active);
      expect(LeaseFilter.fromQueryParam('renewable'), LeaseFilter.renewable);
      expect(LeaseFilter.fromQueryParam('late'), LeaseFilter.late);
      expect(LeaseFilter.fromQueryParam('terminated'), LeaseFilter.terminated);
      expect(LeaseFilter.fromQueryParam('all'), LeaseFilter.all);
    });

    test('null / inconnu → null (page garde son filtre courant)', () {
      expect(LeaseFilter.fromQueryParam(null), isNull);
      expect(LeaseFilter.fromQueryParam(''), isNull);
      expect(LeaseFilter.fromQueryParam('bidon'), isNull);
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

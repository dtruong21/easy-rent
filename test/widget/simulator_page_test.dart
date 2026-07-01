/// Tests widget pour [SimulatorPage] (FEAT-018).
///
/// Couvre : rendu form, validators, disclaimer, save dialog, load scenario.
library;

import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/simulator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

final _fakeScenario = InvestmentScenario(
  id: 'scenario-abc',
  landlordId: 'lld-1',
  name: 'Scénario existant',
  purchasePriceCents: 20000000,
  notaryFeesCents: 1500000,
  loanPrincipalCents: 16000000,
  loanRateBps: 350,
  loanDurationMonths: 240,
  monthlyRentHcCents: 80000,
  propertyTaxAnnualCents: 120000,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeRepo implements InvestmentScenarioRepository {
  final List<InvestmentScenario> scenarios;
  InvestmentScenario? created;
  InvestmentScenario? updated;
  String? deleted;

  _FakeRepo({List<InvestmentScenario>? scenarios})
    : scenarios = scenarios ?? [];

  @override
  Future<List<InvestmentScenario>> list() async => scenarios;

  @override
  Future<InvestmentScenario> getById(String id) async {
    return scenarios.firstWhere(
      (s) => s.id == id,
      orElse: () => throw InvestmentScenarioNotFoundException(id),
    );
  }

  @override
  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents = 0,
    int worksInitialCents = 0,
    bool isNewProperty = false,
    int downPaymentCents = 0,
    int loanPrincipalCents = 0,
    int loanRateBps = 0,
    int loanDurationMonths = 240,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents = 0,
    int insurancePnoAnnualCents = 0,
    int condoFeesNonRecoverableCents = 0,
    String? notes,
  }) async {
    created = InvestmentScenario(
      id: 'new-id',
      landlordId: 'lld-1',
      name: name,
      purchasePriceCents: purchasePriceCents,
      monthlyRentHcCents: monthlyRentHcCents,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    return created!;
  }

  @override
  Future<InvestmentScenario> update(InvestmentScenario scenario) async {
    updated = scenario;
    return scenario;
  }

  @override
  Future<void> softDelete(String id) async {
    deleted = id;
  }
}

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildPage({_FakeRepo? repo}) {
  final fakeRepo = repo ?? _FakeRepo();
  final router = GoRouter(
    initialLocation: '/simulator',
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (context, state) => const SimulatorPage(),
      ),
      GoRoute(
        path: '/simulator/:id',
        builder: (context, state) =>
            SimulatorPage(scenarioId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('Dashboard')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      investmentScenarioRepositoryProvider.overrideWithValue(fakeRepo),
      investmentScenariosListProvider.overrideWith(
        () => _FakeListNotifier(fakeRepo.scenarios),
      ),
      // BAILLAN-M1 : SimulatorPage lit désormais sessionStateProvider (pour
      // AnonDemoBanner) et landlordTierProvider (pour TierChip + enforcement
      // de la limite). Ces tests pré-datent le concept de tier — on fixe un
      // compte complet FREE (aucune restriction pertinente ici, la limite
      // FREE est 3 et les fixtures ne dépassent jamais 1 scénario).
      sessionStateProvider.overrideWithValue(SessionState.fullyAuthenticated),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(
          const LandlordTierSnapshot(tier: SubscriptionTier.free),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Notifier factice pour la liste de scénarios.
///
/// Étend [InvestmentScenariosListNotifier] pour être compatible avec le type
/// attendu par [investmentScenariosListProvider].
class _FakeListNotifier extends InvestmentScenariosListNotifier {
  final List<InvestmentScenario> _scenarios;

  _FakeListNotifier(this._scenarios);

  @override
  Future<List<InvestmentScenario>> build() async => _scenarios;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SimulatorPage — rendu initial', () {
    testWidgets('affiche le titre AppBar', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.text("Simulateur d'investissement"), findsOneWidget);
    });

    testWidgets('affiche le disclaimer permanent', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Estimation indicative basée sur les données saisies. '
          'Ne constitue pas un conseil en investissement. '
          'Consultez un professionnel.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('affiche le bouton sauvegarder', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_scenario_button')), findsOneWidget);
    });

    testWidgets('affiche la section Acquisition avec ExpansionTile', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('section_acquisition')), findsOneWidget);
    });

    testWidgets('affiche la section Financement', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('section_financement')), findsOneWidget);
    });

    testWidgets('affiche la section Revenus locatifs', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('section_revenus')), findsOneWidget);
    });

    testWidgets('affiche la section Charges annuelles', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('section_charges')), findsOneWidget);
    });

    testWidgets('pas de résultats sans prix achat ni loyer', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.text('Résultats estimés'), findsNothing);
    });

    testWidgets('affiche hint quand résultats vides', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(
        find.textContaining("Saisissez le prix d'achat", findRichText: false),
        findsOneWidget,
      );
    });
  });

  group('SimulatorPage — champs obligatoires', () {
    testWidgets('prix achat requis → affiche erreur si vide', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      // Scroll jusqu'au bouton puis clique.
      final saveBtn = find.byKey(const Key('save_scenario_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // La validation form doit rejeter (pas de dialog ouvert).
      expect(find.byKey(const Key('save_scenario_name_field')), findsNothing);
    });

    testWidgets('champ prix achat est présent et activé', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('field_purchase_price')), findsOneWidget);
    });

    testWidgets('champ loyer mensuel est présent', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('field_monthly_rent')), findsOneWidget);
    });
  });

  group('SimulatorPage — save dialog', () {
    testWidgets('ouvre le dialog de nomination après validation réussie', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      // Saisie prix achat.
      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      // Saisie loyer.
      await tester.enterText(
        find.byKey(const Key('field_monthly_rent')),
        '800',
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Scroll et clique sauvegarder → dialog.
      final saveBtn = find.byKey(const Key('save_scenario_button'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save_scenario_name_field')), findsOneWidget);
    });

    testWidgets('dialog contient le bouton confirmer', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '150000',
      );
      await tester.enterText(
        find.byKey(const Key('field_monthly_rent')),
        '700',
      );
      await tester.pump(const Duration(milliseconds: 300));

      final saveBtn2 = find.byKey(const Key('save_scenario_button'));
      await tester.ensureVisible(saveBtn2);
      await tester.tap(saveBtn2);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save_scenario_confirm')), findsOneWidget);
    });

    testWidgets('annulation du dialog ne sauvegarde pas', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      await tester.enterText(
        find.byKey(const Key('field_monthly_rent')),
        '800',
      );
      await tester.pump(const Duration(milliseconds: 300));

      final saveBtn3 = find.byKey(const Key('save_scenario_button'));
      await tester.ensureVisible(saveBtn3);
      await tester.tap(saveBtn3);
      await tester.pumpAndSettle();

      // Annulation.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.created, isNull);
    });
  });

  group('SimulatorPage — résultats live', () {
    testWidgets('affiche les résultats après saisie prix + loyer', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      await tester.enterText(
        find.byKey(const Key('field_monthly_rent')),
        '800',
      );

      // Laisse le debounce s'écouler.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Résultats estimés'), findsOneWidget);
    });
  });

  group('SimulatorPage — liste scénarios vide', () {
    testWidgets('pas de section Mes scénarios si liste vide', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeRepo()));
      await tester.pumpAndSettle();
      expect(find.text('Mes scénarios'), findsNothing);
    });
  });

  group('SimulatorPage — liste scénarios non vide', () {
    testWidgets('affiche la section Mes scénarios si scénarios existants', (
      tester,
    ) async {
      final repo = _FakeRepo(scenarios: [_fakeScenario]);
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();
      expect(find.text('Mes scénarios'), findsOneWidget);
    });

    testWidgets('affiche le nom du scénario dans la liste', (tester) async {
      final repo = _FakeRepo(scenarios: [_fakeScenario]);
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();
      expect(find.text('Scénario existant'), findsOneWidget);
    });
  });
}

/// Tests widget pour [SimulatorPage] (FEAT-018).
///
/// Couvre : rendu form, validators, disclaimer, save dialog, load scenario.
library;

import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
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

/// Fake [AuthRepository] minimal — seule [signOut] est exercée par les tests
/// « quitter le mode démo » ; tout autre appel lève via [noSuchMethod].
class _FakeAuthRepository implements AuthRepository {
  bool signOutCalled = false;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

Widget _buildPage({
  _FakeRepo? repo,
  SessionState sessionState = SessionState.fullyAuthenticated,
  SubscriptionTier tier = SubscriptionTier.free,
  AuthRepository? authRepository,
  String initialLocation = '/simulator',
}) {
  final fakeRepo = repo ?? _FakeRepo();
  final router = GoRouter(
    initialLocation: initialLocation,
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
      GoRoute(
        path: '/signup',
        builder: (context, state) => const Scaffold(body: Text('Signup')),
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
      // de la limite). Défaut : compte complet FREE (aucune restriction
      // pertinente ici). Les tests « mode anonyme » passent
      // sessionState/tier anonymous, un [_FakeAuthRepository] pour capturer
      // le signOut, et initialLocation pour le cas /simulator/:id.
      sessionStateProvider.overrideWithValue(sessionState),
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(LandlordTierSnapshot(tier: tier)),
      ),
      if (authRepository != null)
        authRepositoryProvider.overrideWithValue(authRepository),
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

  group('SimulatorPage — pré-remplissage frais de notaire', () {
    String notaryText(WidgetTester tester) {
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('field_notary_fees')),
          matching: find.byType(EditableText),
        ),
      );
      return editable.controller.text;
    }

    testWidgets('prix saisi → notaire pré-rempli à 8 % (ancien)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      await tester.pumpAndSettle();

      expect(notaryText(tester), '16000,00'); // 200 000 × 8 %
    });

    testWidgets('toggle Bien neuf → recalcule à 2 %, retour ancien → 8 %', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      await tester.tap(find.byKey(const Key('field_is_new_property')));
      await tester.pumpAndSettle();
      expect(notaryText(tester), '4000,00'); // 200 000 × 2 %

      await tester.tap(find.byKey(const Key('field_is_new_property')));
      await tester.pumpAndSettle();
      expect(notaryText(tester), '16000,00');
    });

    testWidgets('saisie manuelle fige le champ ; le toggle le ré-arme', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      // L'utilisateur impose sa propre valeur…
      await tester.enterText(
        find.byKey(const Key('field_notary_fees')),
        '12000',
      );
      // …un nouveau prix ne doit PAS l'écraser.
      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '250000',
      );
      await tester.pumpAndSettle();
      expect(notaryText(tester), '12000');

      // Le toggle est une demande explicite du taux standard → ré-arme.
      await tester.tap(find.byKey(const Key('field_is_new_property')));
      await tester.pumpAndSettle();
      expect(notaryText(tester), '5000,00'); // 250 000 × 2 %
    });

    testWidgets('champ vidé → auto-fill ré-armé au prochain prix', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '200000',
      );
      await tester.enterText(
        find.byKey(const Key('field_notary_fees')),
        '12000',
      );
      await tester.enterText(find.byKey(const Key('field_notary_fees')), '');
      await tester.enterText(
        find.byKey(const Key('field_purchase_price')),
        '100000',
      );
      await tester.pumpAndSettle();
      expect(notaryText(tester), '8000,00'); // 100 000 × 8 %
    });

    testWidgets('mode édition : la valeur sauvée n\'est pas écrasée', (
      tester,
    ) async {
      final repo = _FakeRepo(scenarios: [_fakeScenario]);
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      // Charge le scénario existant (notaire sauvé : 15 000 €).
      await tester.tap(find.text('Scénario existant'));
      await tester.pumpAndSettle();

      expect(notaryText(tester), '15000,00');
    });
  });

  group('SimulatorPage — mode anonyme (retour + quitter la démo)', () {
    Widget anonPage({
      _FakeRepo? repo,
      AuthRepository? authRepository,
      String initialLocation = '/simulator',
    }) => _buildPage(
      repo: repo,
      sessionState: SessionState.anonymous,
      tier: SubscriptionTier.anonymous,
      authRepository: authRepository,
      initialLocation: initialLocation,
    );

    testWidgets('anonyme sur /simulator : pas de bouton retour (foyer sans '
        'destination), action Quitter le mode démo présente', (tester) async {
      await tester.pumpWidget(anonPage());
      await tester.pumpAndSettle();

      // La garde router réécrit `/` en `/simulator` pour un anonyme : le
      // back serait une boucle no-op — fallbackRoute null le masque. La
      // sortie passe par l'action « Quitter le mode démo ».
      expect(find.byKey(const Key('app_bar_back')), findsNothing);
      expect(find.byKey(const Key('simulator_quit_demo')), findsOneWidget);
    });

    testWidgets('compte complet : retour présent (→ /), pas d\'action '
        'Quitter', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
      expect(find.byKey(const Key('simulator_quit_demo')), findsNothing);

      await tester.tap(find.byKey(const Key('app_bar_back')));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('tap Quitter → dialog de confirmation', (tester) async {
      await tester.pumpWidget(anonPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('simulator_quit_demo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quit_demo_dialog')), findsOneWidget);
    });

    testWidgets('dialog Annuler → reste sur le simulateur, pas de signOut', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthRepository();
      await tester.pumpWidget(anonPage(authRepository: fakeAuth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('simulator_quit_demo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quit_demo_dialog')), findsNothing);
      expect(find.text("Simulateur d'investissement"), findsOneWidget);
      expect(fakeAuth.signOutCalled, isFalse);
    });

    testWidgets('dialog Quitter → signOut + retour à la racine', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthRepository();
      await tester.pumpWidget(anonPage(authRepository: fakeAuth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('simulator_quit_demo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quit_demo_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(fakeAuth.signOutCalled, isTrue);
      // Le harnais n'a pas de garde : `/` affiche la page marqueur.
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('dialog Créer un compte → navigation /signup, pas de signOut', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthRepository();
      await tester.pumpWidget(anonPage(authRepository: fakeAuth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('simulator_quit_demo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quit_demo_dialog_signup')));
      await tester.pumpAndSettle();

      expect(fakeAuth.signOutCalled, isFalse);
      expect(find.text('Signup'), findsOneWidget);
    });

    testWidgets('anonyme sur /simulator/:id : retour vers /simulator', (
      tester,
    ) async {
      final repo = _FakeRepo(scenarios: [_fakeScenario]);
      await tester.pumpWidget(
        anonPage(repo: repo, initialLocation: '/simulator/scenario-abc'),
      );
      await tester.pumpAndSettle();

      // Scénario chargé (prix 200 000 €), bouton retour présent.
      expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
      await tester.tap(find.byKey(const Key('app_bar_back')));
      await tester.pumpAndSettle();

      // De retour sur la racine du simulateur : formulaire vierge.
      final priceField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('field_purchase_price')),
          matching: find.byType(EditableText),
        ),
      );
      expect(priceField.controller.text, isEmpty);
      expect(find.text("Simulateur d'investissement"), findsOneWidget);
    });
  });
}

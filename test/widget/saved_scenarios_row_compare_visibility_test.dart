/// Tests widget pour l'entrée « Comparer » renforcée de
/// [SavedScenariosRow] (correctif b) et le fix de robustesse du gate Pro.
///
/// Correctif (b) : l'entrée de comparaison est déplacée sous la rangée de
/// scénarios (plus dans le titre) avec une légende, et son bouton actif est
/// plus contrasté (`OutlinedButton.icon` au lieu de `TextButton.icon`).
///
/// Fix de robustesse : `landlordTierProvider` est `AsyncLoading` (sans
/// valeur) tant que le premier snapshot Firestore n'est pas arrivé, et
/// `valueOrNull` est `null` aussi bien pendant ce chargement qu'en cas
/// d'erreur — un abonné Pro ne doit donc JAMAIS voir le cadenas/upsell
/// pendant cette fenêtre, seulement un état neutre désactivé.
library;

import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/presentation/widgets/saved_scenarios_row.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

InvestmentScenario _scenario({required String id, required String name}) {
  return InvestmentScenario(
    id: id,
    landlordId: 'lld-1',
    name: name,
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
}

class _FakeListNotifier extends InvestmentScenariosListNotifier {
  _FakeListNotifier(this._scenarios);
  final List<InvestmentScenario> _scenarios;
  @override
  Future<List<InvestmentScenario>> build() async => _scenarios;
}

Widget _mount({
  required List<InvestmentScenario> scenarios,
  required Stream<LandlordTierSnapshot?> tierStream,
}) {
  final router = GoRouter(
    initialLocation: '/simulator',
    routes: [
      GoRoute(
        path: '/simulator',
        builder: (_, _) => const Scaffold(body: SavedScenariosRow()),
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) => const Scaffold(body: Text('pro-stub')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      investmentScenariosListProvider.overrideWith(
        () => _FakeListNotifier(scenarios),
      ),
      landlordTierProvider.overrideWith((ref) => tierStream),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

void main() {
  group('SavedScenariosRow — entrée Comparer renforcée', () {
    testWidgets('bouton actif = OutlinedButton + légende visible (Pro)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _mount(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tierStream: Stream.value(
            const LandlordTierSnapshot(tier: SubscriptionTier.paid),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('compare_toggle_button'));
      expect(buttonFinder, findsOneWidget);
      // Contraste renforcé : plus un TextButton (emphase la plus basse).
      expect(tester.widget<OutlinedButton>(buttonFinder).onPressed, isNotNull);
      expect(
        find.text('Comparez 2 ou 3 scénarios côte à côte.'),
        findsOneWidget,
      );
    });

    testWidgets('état neutre pendant le chargement du tier — pas de cadenas', (
      tester,
    ) async {
      // Stream qui n'émet jamais : simule un `landlordTierProvider` encore
      // `AsyncLoading` (cas réel d'un abonné Pro dont le 1er snapshot
      // Firestore n'est pas encore arrivé).
      final pending = StreamController<LandlordTierSnapshot?>();
      addTearDown(pending.close);

      await tester.pumpWidget(
        _mount(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tierStream: pending.stream,
        ),
      );
      await tester.pumpAndSettle();

      // Ni verrouillé/upsell...
      expect(find.byKey(const Key('compare_toggle_pro_only')), findsNothing);
      // ...ni actif/cliquable pour entrer en sélection (tier inconnu).
      expect(find.byKey(const Key('compare_toggle_button')), findsNothing);
      // État neutre dédié, désactivé.
      final resolvingFinder = find.byKey(const Key('compare_toggle_resolving'));
      expect(resolvingFinder, findsOneWidget);
      expect(tester.widget<OutlinedButton>(resolvingFinder).onPressed, isNull);
    });

    testWidgets('résout ensuite vers actif pour un abonné Pro (pas de flash '
        'cadenas)', (tester) async {
      final controller = StreamController<LandlordTierSnapshot?>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _mount(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tierStream: controller.stream,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compare_toggle_pro_only')), findsNothing);

      controller.add(const LandlordTierSnapshot(tier: SubscriptionTier.paid));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('compare_toggle_pro_only')), findsNothing);
      expect(find.byKey(const Key('compare_toggle_resolving')), findsNothing);
      final buttonFinder = find.byKey(const Key('compare_toggle_button'));
      expect(buttonFinder, findsOneWidget);
      expect(tester.widget<OutlinedButton>(buttonFinder).onPressed, isNotNull);
    });

    testWidgets('résout ensuite vers verrouillé pour un compte free', (
      tester,
    ) async {
      final controller = StreamController<LandlordTierSnapshot?>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _mount(
          scenarios: [
            _scenario(id: 'A', name: 'Alpha'),
            _scenario(id: 'B', name: 'Bravo'),
          ],
          tierStream: controller.stream,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compare_toggle_resolving')), findsOneWidget);

      controller.add(const LandlordTierSnapshot(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('compare_toggle_resolving')), findsNothing);
      expect(find.byKey(const Key('compare_toggle_pro_only')), findsOneWidget);
    });
  });
}

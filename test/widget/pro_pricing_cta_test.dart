/// Tests widget de [buildPaidLevelCta] — passage mensuel ↔ annuel à palier
/// constant (FEAT-056). Le gate global est injecté (`subscriptionsEnabled`) :
/// `Env.subscriptionsEnabled` est figé à `false` dans `flutter test`, la page
/// entière ne peut donc pas exercer le chemin « vente ouverte ».
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/domain/plan_entitlement.dart';
import 'package:easyrent/features/auth/domain/plan_level.dart';
import 'package:easyrent/features/auth/domain/plan_matrix.g.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_pricing_cta.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlanLevelSpec _spec(String id) =>
    PlanMatrix.levels.firstWhere((spec) => spec.id == id);

PlanEntitlement _paid(String id) => PlanEntitlement(
  tier: SubscriptionTier.paid,
  level: PlanLevel.values.firstWhere((l) => l.id == id),
);

Future<int> _pump(
  WidgetTester tester, {
  required PlanEntitlement plan,
  required String levelId,
  String? proStore = 'web',
  bool annual = true,
  String? currentPeriod = 'monthly',
  bool subscriptionsEnabled = true,
  bool planChangeLoading = false,
}) async {
  var switches = 0;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => buildPaidLevelCta(
            context,
            plan: plan,
            proStore: proStore,
            spec: _spec(levelId),
            checkoutLoading: false,
            planChangeLoading: planChangeLoading,
            notifyLoading: false,
            notified: false,
            annual: annual,
            currentPeriod: currentPeriod,
            onCheckout: () {},
            onChangePlan: (_) {},
            onSwitchPeriod: () => switches++,
            onNotifyMe: () {},
            subscriptionsEnabled: subscriptionsEnabled,
          ),
        ),
      ),
    ),
  );
  final button = find.byType(OutlinedButton);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button, warnIfMissed: false);
  }
  return switches;
}

const _switchPro = Key('btn_plan_switch_period_pro');

void main() {
  group('palier détenu — passage mensuel ↔ annuel', () {
    testWidgets('abonné web Pro, interrupteur annuel → « Passer à la '
        'facturation annuelle », à côté de l\'offre actuelle', (tester) async {
      final switches = await _pump(tester, plan: _paid('pro'), levelId: 'pro');

      expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
      expect(find.byKey(_switchPro), findsOneWidget);
      expect(find.text('Passer à la facturation annuelle'), findsOneWidget);
      expect(switches, 1);
    });

    testWidgets('abonné annuel, interrupteur mensuel → « Passer à la '
        'facturation mensuelle »', (tester) async {
      await _pump(
        tester,
        plan: _paid('pro'),
        levelId: 'pro',
        annual: false,
        currentPeriod: 'annual',
      );

      expect(find.text('Passer à la facturation mensuelle'), findsOneWidget);
    });

    for (final period in ['monthly', 'annual']) {
      testWidgets('déjà facturé en $period, interrupteur sur $period → pas '
          'de bouton (le passage ne changerait rien)', (tester) async {
        await _pump(
          tester,
          plan: _paid('pro'),
          levelId: 'pro',
          annual: period == 'annual',
          currentPeriod: period,
        );

        expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
        expect(find.byKey(_switchPro), findsNothing);
      });
    }

    testWidgets('périodicité inconnue (chargement, erreur, prix historique) → '
        'pas de bouton', (tester) async {
      await _pump(
        tester,
        plan: _paid('pro'),
        levelId: 'pro',
        currentPeriod: null,
      );

      expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
      expect(find.byKey(_switchPro), findsNothing);
    });

    testWidgets('changement en cours → bouton désactivé', (tester) async {
      final switches = await _pump(
        tester,
        plan: _paid('pro'),
        levelId: 'pro',
        planChangeLoading: true,
      );

      expect(switches, 0);
    });

    for (final store in ['app_store', 'play_store']) {
      testWidgets('abonné $store → pas de bouton (géré dans le store)', (
        tester,
      ) async {
        await _pump(
          tester,
          plan: _paid('pro'),
          levelId: 'pro',
          proStore: store,
        );

        expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
        expect(find.byKey(_switchPro), findsNothing);
      });
    }

    testWidgets('vente fermée (gate global) → offre actuelle seule', (
      tester,
    ) async {
      await _pump(
        tester,
        plan: _paid('pro'),
        levelId: 'pro',
        subscriptionsEnabled: false,
      );

      expect(find.byKey(const Key('btn_plan_current_pro')), findsOneWidget);
      expect(find.byKey(_switchPro), findsNothing);
    });

    testWidgets('palier non achetable (Max) → offre actuelle seule', (
      tester,
    ) async {
      await _pump(tester, plan: _paid('max'), levelId: 'max');

      expect(find.byKey(const Key('btn_plan_current_max')), findsOneWidget);
      expect(find.byKey(const Key('btn_plan_switch_period_max')), findsNothing);
    });

    testWidgets('carte d\'un autre palier → pas de bouton de périodicité', (
      tester,
    ) async {
      await _pump(tester, plan: _paid('max'), levelId: 'pro');

      expect(find.byKey(_switchPro), findsNothing);
      expect(find.byKey(const Key('btn_plan_change_pro')), findsOneWidget);
    });
  });
}

/// Tests widget de [ComingSoonPaidPlanSection].
///
/// Couvre :
/// - Bouton « M'avertir du lancement » → markInterest(features Plan Pro)
/// - Bouton « Participer au financement m'intéresse » →
///   markInterest(['soutien_investisseur']) + verrouillage post-succès
/// - Erreur repo → bouton reste actif (retenter possible)
library;

import 'package:easyrent/features/paid_plan/application/paid_plan_interest_controller.dart';
import 'package:easyrent/features/paid_plan/data/paid_plan_interest_repository.dart';
import 'package:easyrent/features/simulator/presentation/widgets/coming_soon_paid_plan_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePaidPlanInterestRepo implements PaidPlanInterestRepository {
  List<String>? capturedFeatures;
  int calls = 0;
  Exception? error;

  @override
  Future<void> markInterest({
    required List<String> features,
    String? email,
  }) async {
    calls++;
    if (error != null) throw error!;
    capturedFeatures = features;
  }
}

Widget _buildSection(_FakePaidPlanInterestRepo repo) => ProviderScope(
  overrides: [paidPlanInterestRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: ComingSoonPaidPlanSection()),
    ),
  ),
);

void main() {
  group('ComingSoonPaidPlanSection — M\'avertir du lancement', () {
    testWidgets('tap → markInterest avec les features Plan Pro', (
      tester,
    ) async {
      final repo = _FakePaidPlanInterestRepo();
      await tester.pumpWidget(_buildSection(repo));

      await tester.ensureVisible(
        find.byKey(const Key('coming_soon_notify_button')),
      );
      await tester.tap(find.byKey(const Key('coming_soon_notify_button')));
      await tester.pumpAndSettle();

      expect(repo.capturedFeatures, contains('comparateur'));
      expect(find.text('Vous serez prévenu au lancement'), findsOneWidget);
    });
  });

  group('ComingSoonPaidPlanSection — participation au financement', () {
    testWidgets('bloc présent : titre, pitch et bouton', (tester) async {
      await tester.pumpWidget(_buildSection(_FakePaidPlanInterestRepo()));

      expect(find.text('Vous aimez Baillan ?'), findsOneWidget);
      expect(
        find.textContaining('participer à son financement'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('funding_interest_button')), findsOneWidget);
      expect(
        find.text('Participer au financement m\'intéresse'),
        findsOneWidget,
      );
    });

    testWidgets(
      'tap → markInterest([soutien_investisseur]) + bouton verrouillé '
      'avec remerciement',
      (tester) async {
        final repo = _FakePaidPlanInterestRepo();
        await tester.pumpWidget(_buildSection(repo));

        await tester.ensureVisible(
          find.byKey(const Key('funding_interest_button')),
        );
        await tester.tap(find.byKey(const Key('funding_interest_button')));
        await tester.pumpAndSettle();

        expect(repo.capturedFeatures, [fundingInterestKey]);
        expect(find.text('Merci ! Nous vous recontacterons'), findsOneWidget);
        expect(
          find.textContaining('Merci pour votre soutien'),
          findsOneWidget,
        ); // snackbar

        final btn = tester.widget<OutlinedButton>(
          find.byKey(const Key('funding_interest_button')),
        );
        expect(btn.onPressed, isNull);
      },
    );

    testWidgets('erreur repo → pas de faux succès, bouton retentable', (
      tester,
    ) async {
      final repo = _FakePaidPlanInterestRepo()
        ..error = Exception('permission-denied');
      await tester.pumpWidget(_buildSection(repo));

      await tester.ensureVisible(
        find.byKey(const Key('funding_interest_button')),
      );
      await tester.tap(find.byKey(const Key('funding_interest_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Participer au financement m\'intéresse'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Impossible d\'enregistrer votre intérêt'),
        findsOneWidget,
      );

      final btn = tester.widget<OutlinedButton>(
        find.byKey(const Key('funding_interest_button')),
      );
      expect(btn.onPressed, isNotNull);
    });
  });
}

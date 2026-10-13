/// Tests widget de [ProBadge] (FEAT-056 PR-6) — affiche le palier réel
/// (Pro/Max/Ultra) plutôt qu'un simple état payant/gratuit.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/paid_plan/presentation/pro_badge.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildBadge({required SubscriptionTier tier, String? planLevel}) =>
    ProviderScope(
      overrides: [
        landlordTierProvider.overrideWith(
          (ref) => Stream.value(
            LandlordTierSnapshot(tier: tier, planLevel: planLevel),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
        home: const Scaffold(body: ProBadge()),
      ),
    );

void main() {
  group('ProBadge — masqué pour les comptes non payants', () {
    testWidgets('tier free → rien affiché', (tester) async {
      await tester.pumpWidget(_buildBadge(tier: SubscriptionTier.free));
      await tester.pumpAndSettle();
      expect(find.text('PRO'), findsNothing);
      expect(find.text('MAX'), findsNothing);
      expect(find.text('ULTRA'), findsNothing);
    });

    testWidgets('tier anonymous → rien affiché', (tester) async {
      await tester.pumpWidget(_buildBadge(tier: SubscriptionTier.anonymous));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro_badge_pro')), findsNothing);
    });
  });

  group('ProBadge — palier réel affiché', () {
    testWidgets('paid, planLevel=pro → "PRO"', (tester) async {
      await tester.pumpWidget(
        _buildBadge(tier: SubscriptionTier.paid, planLevel: 'pro'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro_badge_pro')), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('paid, planLevel=max → "MAX"', (tester) async {
      await tester.pumpWidget(
        _buildBadge(tier: SubscriptionTier.paid, planLevel: 'max'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro_badge_max')), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
    });

    testWidgets('paid, planLevel=ultra → "ULTRA"', (tester) async {
      await tester.pumpWidget(
        _buildBadge(tier: SubscriptionTier.paid, planLevel: 'ultra'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro_badge_ultra')), findsOneWidget);
      expect(find.text('ULTRA'), findsOneWidget);
    });

    testWidgets(
      'paid sans planLevel (legacy) → grandfathering I3, affiche "PRO"',
      (tester) async {
        await tester.pumpWidget(_buildBadge(tier: SubscriptionTier.paid));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pro_badge_pro')), findsOneWidget);
        expect(find.text('PRO'), findsOneWidget);
      },
    );
  });
}

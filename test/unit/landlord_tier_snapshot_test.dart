/// Tests de mapping Firestore → [LandlordTierSnapshot] pour
/// [FirestoreLandlordTierRepository.watch] (FEAT-044f).
///
/// Couvre l'extension du snapshot avec les champs `proWillRenew`,
/// `proExpiresAt`, `proStore`, `proEntitlementActive` écrits par
/// `revenuecat_webhook.ts` / `reconcile_entitlements.ts` — présents, absents
/// (compte free/anonyme jamais passé par le webhook), ou `null` explicite.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'lld-tier-1';

void main() {
  group('FirestoreLandlordTierRepository.watch — champs pro* (FEAT-044f)', () {
    test(
      'doc complet (abonné Pro web, renouvelable) → tous les champs mappés',
      () async {
        final firestore = FakeFirebaseFirestore();
        final expiresAt = DateTime.utc(2026, 8, 15);
        await firestore.doc('landlords/$_uid').set({
          'subscriptionTier': 'paid',
          'proWillRenew': true,
          'proExpiresAt': Timestamp.fromDate(expiresAt),
          'proStore': 'web',
          'proEntitlementActive': true,
        });
        final repo = FirestoreLandlordTierRepository(firestore);

        final snapshot = await repo.watch(_uid).first;

        expect(snapshot, isNotNull);
        expect(snapshot!.tier, SubscriptionTier.paid);
        expect(snapshot.proWillRenew, isTrue);
        // `Timestamp.toDate()` peut revenir en heure locale (même instant,
        // représentation différente) — comparaison par instant, pas par
        // égalité stricte de représentation (cf. `DateTime.==` vs
        // `isAtSameMomentAs`).
        expect(snapshot.proExpiresAt!.isAtSameMomentAs(expiresAt), isTrue);
        expect(snapshot.proStore, 'web');
        expect(snapshot.proEntitlementActive, isTrue);
      },
    );

    test(
      'résiliation programmée (proWillRenew: false) → mappé fidèlement',
      () async {
        final firestore = FakeFirebaseFirestore();
        final expiresAt = DateTime.utc(2026, 9, 1);
        await firestore.doc('landlords/$_uid').set({
          'subscriptionTier': 'paid',
          'proWillRenew': false,
          'proExpiresAt': Timestamp.fromDate(expiresAt),
          'proStore': 'web',
          'proEntitlementActive': true,
        });
        final repo = FirestoreLandlordTierRepository(firestore);

        final snapshot = await repo.watch(_uid).first;

        expect(snapshot!.proWillRenew, isFalse);
        expect(snapshot.proExpiresAt!.isAtSameMomentAs(expiresAt), isTrue);
      },
    );

    test('abonné mobile (proStore=app_store) → store mappé tel quel', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('landlords/$_uid').set({
        'subscriptionTier': 'paid',
        'proWillRenew': true,
        'proStore': 'app_store',
        'proEntitlementActive': true,
      });
      final repo = FirestoreLandlordTierRepository(firestore);

      final snapshot = await repo.watch(_uid).first;

      expect(snapshot!.proStore, 'app_store');
    });

    test(
      'compte free — champs pro* absents du doc → tous null, tier free',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.doc('landlords/$_uid').set({
          'subscriptionTier': 'free',
        });
        final repo = FirestoreLandlordTierRepository(firestore);

        final snapshot = await repo.watch(_uid).first;

        expect(snapshot!.tier, SubscriptionTier.free);
        expect(snapshot.proWillRenew, isNull);
        expect(snapshot.proExpiresAt, isNull);
        expect(snapshot.proStore, isNull);
        expect(snapshot.proEntitlementActive, isNull);
      },
    );

    test(
      'champs pro* explicitement null dans Firestore → mappés en null (pas de crash)',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.doc('landlords/$_uid').set({
          'subscriptionTier': 'free',
          'proWillRenew': null,
          'proExpiresAt': null,
          'proStore': null,
          'proEntitlementActive': null,
        });
        final repo = FirestoreLandlordTierRepository(firestore);

        final snapshot = await repo.watch(_uid).first;

        expect(snapshot!.proWillRenew, isNull);
        expect(snapshot.proExpiresAt, isNull);
        expect(snapshot.proStore, isNull);
        expect(snapshot.proEntitlementActive, isNull);
      },
    );

    test(
      'doc anonyme (anonExpiresAt) — champs pro* absents, anonExpiresAt préservé',
      () async {
        final firestore = FakeFirebaseFirestore();
        final anonExpiresAt = DateTime.utc(2026, 8, 7);
        await firestore.doc('landlords/$_uid').set({
          'subscriptionTier': 'anonymous',
          'anonExpiresAt': Timestamp.fromDate(anonExpiresAt),
        });
        final repo = FirestoreLandlordTierRepository(firestore);

        final snapshot = await repo.watch(_uid).first;

        expect(snapshot!.tier, SubscriptionTier.anonymous);
        expect(snapshot.anonExpiresAt!.isAtSameMomentAs(anonExpiresAt), isTrue);
        expect(snapshot.proWillRenew, isNull);
        expect(snapshot.proExpiresAt, isNull);
        expect(snapshot.proStore, isNull);
        expect(snapshot.proEntitlementActive, isNull);
      },
    );

    test('doc inexistant → null (aucun crash)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreLandlordTierRepository(firestore);

      final snapshot = await repo.watch(_uid).first;

      expect(snapshot, isNull);
    });
  });
}

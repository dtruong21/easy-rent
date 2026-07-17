import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrat SEED ↔ APP. Le script `tool/seed/seed_tiers.mjs` (et tout chemin
/// serveur type webhook de paiement) écrit `subscriptionTier` sous forme de
/// chaîne brute dans Firestore ; l'app la relit via [SubscriptionTier.fromRaw].
/// Si un jour la valeur brute d'un palier change d'un côté sans l'autre, un
/// doc `paid` semé se relirait en `anonymous` (fail-safe) et l'utilisateur
/// perdrait silencieusement son plan. Ces tests figent ce contrat.
///
/// Ils couvrent aussi les getters de plafonds ([scenarioLimit], etc.) — la
/// matrice freemium (FEAT-044) — qui n'étaient testés qu'indirectement via les
/// providers du simulateur, jamais sur l'enum lui-même.
void main() {
  group('SubscriptionTier — round-trip raw ↔ enum (contrat seed)', () {
    test('chaque palier survit à un aller-retour raw → fromRaw', () {
      for (final tier in SubscriptionTier.values) {
        expect(
          SubscriptionTier.fromRaw(tier.raw),
          tier,
          reason:
              'le palier $tier ne round-trip pas via sa valeur brute '
              '"${tier.raw}"',
        );
      }
    });

    test('valeurs brutes exactes attendues par Firestore / le seed', () {
      // Ces littéraux sont le contrat écrit par tool/seed/seed_tiers.mjs et les
      // Cloud Functions. Les changer ici DOIT s'accompagner d'une migration.
      expect(SubscriptionTier.anonymous.raw, 'anonymous');
      expect(SubscriptionTier.free.raw, 'free');
      expect(SubscriptionTier.paid.raw, 'paid');
    });
  });

  group('SubscriptionTier.fromRaw — fail-safe', () {
    test('null → anonymous (palier le plus restrictif)', () {
      expect(SubscriptionTier.fromRaw(null), SubscriptionTier.anonymous);
    });

    test('valeur inconnue → anonymous (jamais sur-privilégier)', () {
      expect(SubscriptionTier.fromRaw('gold'), SubscriptionTier.anonymous);
      expect(SubscriptionTier.fromRaw(''), SubscriptionTier.anonymous);
      // Sensible à la casse : 'Paid' n'est PAS 'paid' → retombe en anonymous.
      expect(SubscriptionTier.fromRaw('Paid'), SubscriptionTier.anonymous);
    });
  });

  group('SubscriptionTier — plafonds freemium (FEAT-044)', () {
    test('scénarios simulateur : anon 1 / free 3 / paid illimité', () {
      expect(SubscriptionTier.anonymous.scenarioLimit, 1);
      expect(SubscriptionTier.free.scenarioLimit, 3);
      expect(SubscriptionTier.paid.scenarioLimit, isNull);
    });

    test('biens : anon 0 / free 2 / paid illimité', () {
      expect(SubscriptionTier.anonymous.propertyLimit, 0);
      expect(SubscriptionTier.free.propertyLimit, 2);
      expect(SubscriptionTier.paid.propertyLimit, isNull);
    });

    test('locataires actifs : anon 0 / free 3 / paid illimité', () {
      expect(SubscriptionTier.anonymous.activeTenantLimit, 0);
      expect(SubscriptionTier.free.activeTenantLimit, 3);
      expect(SubscriptionTier.paid.activeTenantLimit, isNull);
    });

    test('baux actifs : anon 0 / free 2 / paid illimité', () {
      expect(SubscriptionTier.anonymous.activeLeaseLimit, 0);
      expect(SubscriptionTier.free.activeLeaseLimit, 2);
      expect(SubscriptionTier.paid.activeLeaseLimit, isNull);
    });

    test('paid = aucun plafond sur aucune dimension', () {
      // Invariant transverse : le palier payant n'est jamais limité. Garde
      // contre l'ajout d'une nouvelle dimension de plafond qui oublierait
      // d'exempter `paid`.
      expect(SubscriptionTier.paid.scenarioLimit, isNull);
      expect(SubscriptionTier.paid.propertyLimit, isNull);
      expect(SubscriptionTier.paid.activeTenantLimit, isNull);
      expect(SubscriptionTier.paid.activeLeaseLimit, isNull);
    });
  });
}

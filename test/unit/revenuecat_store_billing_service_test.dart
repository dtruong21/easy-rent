/// Tests de [RevenueCatStoreBillingService] : mappers purs et comportement
/// « non configuré » (achat intégré coupé dans `flutter test` : IAP_ENABLED
/// absent, donc aucun appel au SDK).
library;

import 'package:easyrent/features/paid_plan/data/revenuecat_store_billing_service.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/domain/store_billing_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() {
  group('purchaseOutcomeForError', () {
    test('annulation → PurchaseCancelled', () {
      expect(
        purchaseOutcomeForError(PurchasesErrorCode.purchaseCancelledError),
        isA<PurchaseCancelled>(),
      );
    });

    test('paiement en attente → PurchasePending', () {
      expect(
        purchaseOutcomeForError(PurchasesErrorCode.paymentPendingError),
        isA<PurchasePending>(),
      );
    });

    test('autre erreur → PurchaseFailed avec le nom du code', () {
      for (final code in [
        PurchasesErrorCode.storeProblemError,
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.productAlreadyPurchasedError,
      ]) {
        expect(
          purchaseOutcomeForError(code),
          isA<PurchaseFailed>().having((f) => f.code, 'code', code.name),
        );
      }
    });

    PurchaseFailureReason reasonFor(PurchasesErrorCode code) =>
        (purchaseOutcomeForError(code) as PurchaseFailed).reason;

    test('produit déjà actif sur le compte store → alreadyOwned', () {
      expect(
        reasonFor(PurchasesErrorCode.productAlreadyPurchasedError),
        PurchaseFailureReason.alreadyOwned,
      );
    });

    test('reçu utilisé par un autre abonné → ownedByAnotherAccount', () {
      for (final code in [
        PurchasesErrorCode.receiptAlreadyInUseError,
        PurchasesErrorCode.receiptInUseByOtherSubscriberError,
      ]) {
        expect(
          reasonFor(code),
          PurchaseFailureReason.ownedByAnotherAccount,
          reason: code.name,
        );
      }
    });

    test('toute autre erreur → other', () {
      for (final code in [
        PurchasesErrorCode.storeProblemError,
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.unknownError,
      ]) {
        expect(reasonFor(code), PurchaseFailureReason.other, reason: code.name);
      }
    });
  });

  group('errorCodeOrNull', () {
    test('code numérique valide → le PurchasesErrorCode correspondant', () {
      final code = PurchasesErrorCode.purchaseCancelledError;
      expect(errorCodeOrNull(PlatformException(code: '${code.index}')), code);
    });

    test('code hors plage → unknownError (comportement du SDK)', () {
      expect(
        errorCodeOrNull(PlatformException(code: '9999')),
        PurchasesErrorCode.unknownError,
      );
    });

    test('code non numérique → null, sans exception', () {
      expect(errorCodeOrNull(PlatformException(code: 'abc')), isNull);
    });

    test('code négatif → null, sans exception', () {
      expect(errorCodeOrNull(PlatformException(code: '-1')), isNull);
    });
  });

  group('restoreOutcomeFor', () {
    test('aucun entitlement actif → nothingToRestore', () {
      expect(
        restoreOutcomeFor(activeEntitlements: 0),
        RestoreOutcome.nothingToRestore,
      );
    });

    test('au moins un entitlement actif → success', () {
      expect(restoreOutcomeFor(activeEntitlements: 1), RestoreOutcome.success);
    });
  });

  group('restoreOutcomeForError', () {
    test('reçu utilisé par un autre abonné → ownedByAnotherAccount', () {
      for (final code in [
        PurchasesErrorCode.receiptAlreadyInUseError,
        PurchasesErrorCode.receiptInUseByOtherSubscriberError,
      ]) {
        expect(
          restoreOutcomeForError(code),
          RestoreOutcome.ownedByAnotherAccount,
          reason: code.name,
        );
      }
    });

    test('autre erreur ou code illisible → error', () {
      expect(
        restoreOutcomeForError(PurchasesErrorCode.networkError),
        RestoreOutcome.error,
      );
      expect(restoreOutcomeForError(null), RestoreOutcome.error);
    });
  });

  group('mapping de l\'offre RevenueCat', () {
    const context = PresentedOfferingContext('default', null, null);
    Package pkg(String id, PackageType type, String price) => Package(
      id,
      type,
      StoreProduct(id, '', 'Pro', 1, price, 'EUR'),
      context,
    );
    final monthly = pkg(r'$rc_monthly', PackageType.monthly, '8,49 €');
    final annual = pkg(r'$rc_annual', PackageType.annual, '84,99 €');
    Offering offering({Package? m, Package? a}) =>
        Offering('default', '', const {}, [?m, ?a], monthly: m, annual: a);

    test('mensuel et annuel → prix du store, sans inversion', () {
      final offer = proOfferFromOffering(offering(m: monthly, a: annual))!;
      expect(offer.monthly!.period, StoreBillingPeriod.monthly);
      expect(offer.monthly!.priceString, '8,49 €');
      expect(offer.annual!.period, StoreBillingPeriod.annual);
      expect(offer.annual!.priceString, '84,99 €');
    });

    test('offre partielle → seule la formule présente', () {
      final offer = proOfferFromOffering(offering(a: annual))!;
      expect(offer.monthly, isNull);
      expect(offer.annual!.priceString, '84,99 €');
    });

    test('aucune offre courante → null', () {
      expect(proOfferFromOffering(null), isNull);
    });

    test('packageForPeriod rend le bon package', () {
      final current = offering(m: monthly, a: annual);
      expect(
        packageForPeriod(current, StoreBillingPeriod.monthly)!.identifier,
        r'$rc_monthly',
      );
      expect(
        packageForPeriod(current, StoreBillingPeriod.annual)!.identifier,
        r'$rc_annual',
      );
      expect(packageForPeriod(null, StoreBillingPeriod.monthly), isNull);
    });
  });

  group('achat intégré coupé (non configuré)', () {
    late RevenueCatStoreBillingService service;
    setUp(() async {
      service = RevenueCatStoreBillingService();
      await service.configure(); // sans effet : IAP_ENABLED absent
    });

    test('offre → null', () async {
      expect(await service.fetchProOffer(), isNull);
    });

    test('achat → PurchaseFailed(not_configured)', () async {
      final outcome = await service.purchase(
        const ProStorePackage(
          period: StoreBillingPeriod.monthly,
          priceString: '7,99 €',
        ),
        uid: 'u1',
      );
      expect(
        outcome,
        isA<PurchaseFailed>().having((f) => f.code, 'code', 'not_configured'),
      );
    });

    test('restauration → error', () async {
      expect(await service.restore(uid: 'u1'), RestoreOutcome.error);
    });

    test('page de gestion → null', () async {
      expect(await service.managementUrl(), isNull);
    });

    test('droit actif côté store → false (jamais de faux positif)', () async {
      expect(await service.hasActiveEntitlement(uid: 'u1'), isFalse);
    });

    test('logIn / logOut → sans effet ni exception', () async {
      await service.logIn('u1');
      await service.logOut();
    });
  });

  test('le provider fournit le service RevenueCat', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(storeBillingServiceProvider),
      isA<RevenueCatStoreBillingService>(),
    );
  });
}

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
      );
      expect(
        outcome,
        isA<PurchaseFailed>().having((f) => f.code, 'code', 'not_configured'),
      );
    });

    test('restauration → error', () async {
      expect(await service.restore(), RestoreOutcome.error);
    });

    test('page de gestion → null', () async {
      expect(await service.managementUrl(), isNull);
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

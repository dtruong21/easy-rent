import 'dart:async';

import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/domain/store_billing_models.dart';

/// Faux [StoreBillingService] : journalise chaque appel dans [calls] et rend
/// les issues configurées. [logInGate] retient `logIn` jusqu'à sa complétion
/// (tests de sérialisation) ; [logInError] fait échouer `logIn`.
class FakeStoreBillingService implements StoreBillingService {
  final List<String> calls = [];
  Completer<void>? logInGate;
  Object? logInError;
  ProStoreOffer? offer;
  PurchaseOutcome purchaseOutcome = const PurchaseSucceeded();
  RestoreOutcome restoreOutcome = RestoreOutcome.nothingToRestore;
  Uri? management;

  /// Retient `purchase` jusqu'à sa complétion (tests « achat en cours »).
  Completer<void>? purchaseGate;
  int offerCalls = 0;

  @override
  Future<void> configure() async => calls.add('configure');

  @override
  Future<void> logIn(String uid) async {
    calls.add('logIn:$uid');
    if (logInGate != null) await logInGate!.future;
    if (logInError != null) throw logInError!;
  }

  @override
  Future<void> logOut() async => calls.add('logOut');

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    offerCalls++;
    calls.add('fetchProOffer');
    return offer;
  }

  @override
  Future<PurchaseOutcome> purchase(
    ProStorePackage package, {
    required String uid,
  }) async {
    calls.add('purchase:${package.period.name}:$uid');
    if (purchaseGate != null) await purchaseGate!.future;
    return purchaseOutcome;
  }

  @override
  Future<RestoreOutcome> restore({required String uid}) async {
    calls.add('restore:$uid');
    return restoreOutcome;
  }

  /// Le store rapporte déjà un abonnement actif (achat fait, activation
  /// serveur pas encore visible). [entitlementGate] retient la réponse.
  bool activeEntitlement = false;
  Completer<void>? entitlementGate;
  int entitlementCalls = 0;

  @override
  Future<bool> hasActiveEntitlement({required String uid}) async {
    entitlementCalls++;
    calls.add('hasActiveEntitlement:$uid');
    if (entitlementGate != null) await entitlementGate!.future;
    return activeEntitlement;
  }

  @override
  Future<Uri?> managementUrl() async {
    calls.add('managementUrl');
    return management;
  }
}

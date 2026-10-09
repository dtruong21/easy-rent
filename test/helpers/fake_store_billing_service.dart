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
    calls.add('fetchProOffer');
    return offer;
  }

  @override
  Future<PurchaseOutcome> purchase(ProStorePackage package) async {
    calls.add('purchase:${package.period.name}');
    return purchaseOutcome;
  }

  @override
  Future<RestoreOutcome> restore() async {
    calls.add('restore');
    return restoreOutcome;
  }

  @override
  Future<Uri?> managementUrl() async {
    calls.add('managementUrl');
    return management;
  }
}

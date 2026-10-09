import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/config/store_billing.dart';
import '../domain/store_billing_models.dart';
import 'store_billing_service.dart';

final _log = Logger('RevenueCatStoreBillingService');

/// PURE — issue d'un achat selon le code d'erreur du SDK.
@visibleForTesting
PurchaseOutcome purchaseOutcomeForError(PurchasesErrorCode code) =>
    switch (code) {
      PurchasesErrorCode.purchaseCancelledError => const PurchaseCancelled(),
      PurchasesErrorCode.paymentPendingError => const PurchasePending(),
      _ => PurchaseFailed(code.name),
    };

/// PURE — code d'erreur du SDK pour [e], ou `null` si illisible. Le SDK fait
/// `num.parse(e.code)` puis indexe l'enum : un code non numérique lève
/// `FormatException`, un code négatif `RangeError` — jamais à laisser
/// remonter depuis un gestionnaire d'erreur.
@visibleForTesting
PurchasesErrorCode? errorCodeOrNull(PlatformException e) {
  try {
    return PurchasesErrorHelper.getErrorCode(e);
  } catch (_) {
    return null;
  }
}

/// PURE — restauration : au moins un entitlement actif → droit retrouvé
/// (le palier lui-même vient du serveur).
@visibleForTesting
RestoreOutcome restoreOutcomeFor({required int activeEntitlements}) =>
    activeEntitlements > 0
    ? RestoreOutcome.success
    : RestoreOutcome.nothingToRestore;

/// Implémentation RevenueCat — SEULE classe de `lib/` qui importe
/// `purchases_flutter`. Non configurée (achat intégré coupé, clé absente,
/// échec du SDK) : chaque méthode est sans effet ou rend une issue neutre.
class RevenueCatStoreBillingService implements StoreBillingService {
  bool _configured = false;

  @override
  Future<void> configure() async {
    if (_configured || !isStoreApp || !Env.iapEnabled) return;
    final key = revenueCatApiKeyFor(defaultTargetPlatform);
    if (key == null) {
      _log.severe(
        'IAP_ENABLED sans clé RevenueCat pour $defaultTargetPlatform : '
        'achat intégré coupé',
      );
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
    } catch (e, st) {
      _log.severe('configuration RevenueCat impossible : achat coupé', e, st);
    }
  }

  @override
  Future<void> logIn(String uid) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(uid);
    } catch (e, st) {
      _log.warning('logIn RevenueCat échoué', e, st);
      // Seule méthode qui relance : l'appelant doit savoir que le compte n'est
      // pas rattaché (réseau…) pour réessayer, sinon l'achat du lot 3 partirait
      // sur l'id anonyme RevenueCat.
      rethrow;
    }
  }

  @override
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (e, st) {
      // Utilisateur déjà anonyme côté RevenueCat : rien à faire.
      if (e is PlatformException &&
          errorCodeOrNull(e) ==
              PurchasesErrorCode.logOutWithAnonymousUserError) {
        return;
      }
      _log.warning('logOut RevenueCat échoué', e, st);
    }
  }

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    if (!_configured) return null;
    try {
      final current = (await Purchases.getOfferings()).current;
      if (current == null) return null;
      ProStorePackage? map(Package? p, StoreBillingPeriod period) => p == null
          ? null
          : ProStorePackage(
              period: period,
              priceString: p.storeProduct.priceString,
            );
      return ProStoreOffer(
        monthly: map(current.monthly, StoreBillingPeriod.monthly),
        annual: map(current.annual, StoreBillingPeriod.annual),
      );
    } catch (e, st) {
      _log.warning('offres RevenueCat indisponibles', e, st);
      return null;
    }
  }

  @override
  Future<PurchaseOutcome> purchase(ProStorePackage package) async {
    if (!_configured) return const PurchaseFailed('not_configured');
    try {
      final current = (await Purchases.getOfferings()).current;
      final pkg = switch (package.period) {
        StoreBillingPeriod.monthly => current?.monthly,
        StoreBillingPeriod.annual => current?.annual,
      };
      if (pkg == null) return const PurchaseFailed('package_unavailable');
      await Purchases.purchase(PurchaseParams.package(pkg));
      return const PurchaseSucceeded();
    } catch (e, st) {
      // Jamais d'exception vers l'appelant : le bouton d'achat resterait figé.
      final code = e is PlatformException ? errorCodeOrNull(e) : null;
      if (code != null) return purchaseOutcomeForError(code);
      _log.warning('achat RevenueCat échoué', e, st);
      return const PurchaseFailed('unknown');
    }
  }

  @override
  Future<RestoreOutcome> restore() async {
    if (!_configured) return RestoreOutcome.error;
    try {
      final info = await Purchases.restorePurchases();
      return restoreOutcomeFor(
        activeEntitlements: info.entitlements.active.length,
      );
    } catch (e, st) {
      _log.warning('restauration RevenueCat échouée', e, st);
      return RestoreOutcome.error;
    }
  }

  @override
  Future<Uri?> managementUrl() async {
    if (!_configured) return null;
    try {
      final url = (await Purchases.getCustomerInfo()).managementURL;
      return url == null ? null : Uri.tryParse(url);
    } catch (e, st) {
      _log.warning('URL de gestion RevenueCat indisponible', e, st);
      return null;
    }
  }
}

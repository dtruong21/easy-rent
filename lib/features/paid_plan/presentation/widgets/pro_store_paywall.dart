import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../application/store_offer_provider.dart';
import '../../data/store_billing_service.dart';
import '../../domain/store_billing_models.dart';
import '../../domain/store_names.dart';
import 'pro_store_paywall_views.dart';

/// Délai au-delà duquel l'activation est signalée comme lente.
const Duration kStoreActivationTimeout = Duration(seconds: 60);

enum _Phase { offers, activating, delayed }

/// Écran d'achat des apps iOS/Android (FEAT-044e) — corps de `/pro` quand
/// l'achat intégré est actif.
///
/// Le serveur seul accorde le droit : après un achat ou une restauration
/// réussis, l'écran attend que [planEntitlementProvider] passe en Pro (écrit
/// par le webhook RevenueCat). Il ne débloque jamais rien lui-même, et
/// « Réessayer » relance l'attente, jamais un second achat. Si le store voit
/// déjà un abonnement actif à l'ouverture (achat fait, puis écran quitté avant
/// l'activation), l'écran reprend cette attente au lieu de reproposer l'achat.
class ProStorePaywall extends ConsumerStatefulWidget {
  const ProStorePaywall({super.key});

  @override
  ConsumerState<ProStorePaywall> createState() => _ProStorePaywallState();
}

class _ProStorePaywallState extends ConsumerState<ProStorePaywall> {
  _Phase _phase = _Phase.offers;
  bool _busy = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startActivation() {
    _timer?.cancel();
    setState(() => _phase = _Phase.activating);
    _timer = Timer(kStoreActivationTimeout, () {
      if (mounted && _phase == _Phase.activating) {
        setState(() => _phase = _Phase.delayed);
      }
    });
  }

  void _snack(String key, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(key: Key(key), content: Text(message)));
  }

  Future<void> _buy(ProStorePackage package) async {
    // Un second appui avant la prochaine frame ne lance pas un second achat.
    if (_busy) return;
    // `ref` et `context` lus AVANT tout await.
    final service = ref.read(storeBillingServiceProvider);
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final l10n = context.l10n;
    final store = storeNameForPlatform(defaultTargetPlatform);
    if (uid == null) {
      _snack('snackbar_store_purchase_error', l10n.storePurchaseError);
      return;
    }
    setState(() => _busy = true);
    final outcome = await service.purchase(package, uid: uid);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseSucceeded():
        _startActivation();
      case PurchaseCancelled():
        break;
      case PurchasePending():
        _snack('snackbar_store_purchase_pending', l10n.storePurchasePending);
      case PurchaseFailed(:final reason):
        // Abonnement déjà présent côté store : ne pas inviter à réessayer.
        switch (reason) {
          case PurchaseFailureReason.alreadyOwned:
            _snack(
              'snackbar_store_purchase_already_owned',
              l10n.storePurchaseAlreadyOwned(store),
            );
          case PurchaseFailureReason.ownedByAnotherAccount:
            _snack(
              'snackbar_store_purchase_other_account',
              l10n.storeSubscriptionOwnedByAnotherAccount(store),
            );
          case PurchaseFailureReason.other:
            _snack('snackbar_store_purchase_error', l10n.storePurchaseError);
        }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final service = ref.read(storeBillingServiceProvider);
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final l10n = context.l10n;
    final store = storeNameForPlatform(defaultTargetPlatform);
    if (uid == null) {
      _snack('snackbar_store_restore_error', l10n.storeRestoreError);
      return;
    }
    setState(() => _busy = true);
    final outcome = await service.restore(uid: uid);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case RestoreOutcome.success:
        _startActivation();
      case RestoreOutcome.nothingToRestore:
        _snack('snackbar_store_restore_nothing', l10n.storeRestoreNothing);
      case RestoreOutcome.ownedByAnotherAccount:
        _snack(
          'snackbar_store_restore_other_account',
          l10n.storeSubscriptionOwnedByAnotherAccount(store),
        );
      case RestoreOutcome.error:
        _snack('snackbar_store_restore_error', l10n.storeRestoreError);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Le palier doit être RÉGLÉ et PRÉSENT avant toute offre : un abonné ne
    // doit jamais voir, même un instant, de quoi acheter une seconde fois, et
    // un compte sans document `landlords/{uid}` ne pourrait jamais être activé
    // par le webhook (`no_landlord`). Pas connu = en chargement (y compris un
    // rechargement qui garde la valeur précédente, après un changement de
    // compte), en erreur, ou réglé à `null`.
    final tier = ref.watch(landlordTierProvider);
    if (tier.isLoading) return const Center(child: CircularProgressIndicator());
    if (tier.hasError || tier.valueOrNull == null) {
      return StoreOfferUnavailableView(
        onRetry: () => ref.invalidate(landlordTierProvider),
      );
    }
    // Déjà Pro (toute origine) : aucun achat proposé. C'est aussi ce qui
    // termine l'attente d'activation.
    if (ref.watch(planEntitlementProvider).atLeast(PlanLevel.pro)) {
      _timer?.cancel();
      _phase = _Phase.offers;
      return StoreAlreadySubscribedView(onManage: () => context.go('/profile'));
    }
    return switch (_phase) {
      _Phase.activating => const StoreActivatingView(),
      _Phase.delayed => StoreActivationDelayedView(
        busy: _busy,
        onRestore: _restore,
        onRetry: _startActivation,
      ),
      _Phase.offers => _offersOrResumeWait(),
    };
  }

  /// Offres du store — sauf si le store voit déjà un abonnement actif pour ce
  /// compte : l'achat a été fait, puis l'écran quitté avant que le serveur
  /// n'accorde le droit. On reprend alors l'attente au lieu de reproposer
  /// l'achat. Cela n'accorde rien : seul [planEntitlementProvider] y met fin.
  Widget _offersOrResumeWait() {
    final owned = ref.watch(storeActiveEntitlementProvider);
    if (owned.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (owned.valueOrNull ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _Phase.offers) _startActivation();
      });
      return const StoreActivatingView();
    }
    return ref
        .watch(storeProOfferProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => StoreOfferUnavailableView(
            onRetry: () => ref.invalidate(storeProOfferProvider),
          ),
          data: (offer) =>
              offer == null || (offer.monthly == null && offer.annual == null)
              ? StoreOfferUnavailableView(
                  onRetry: () => ref.invalidate(storeProOfferProvider),
                )
              : StoreOffersView(
                  offer: offer,
                  busy: _busy,
                  onBuy: _buy,
                  onRestore: _restore,
                ),
        );
  }
}

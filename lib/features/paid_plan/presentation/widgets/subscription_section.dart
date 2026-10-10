import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/store_billing.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../../profile/presentation/widgets/section_header.dart';
import '../../application/manage_subscription_controller.dart';
import '../../data/store_billing_service.dart';
import '../../data/subscription_repository.dart';
import '../../domain/store_names.dart';
import '../pro_pricing_cta.dart' show mobileStores;
import 'plan_level_label.dart';
import 'subscription_cancel_dialog.dart';
import 'subscription_status_views.dart';

final _log = Logger('SubscriptionSection');

/// Section « Abonnement Baillan Pro » de `/profile` (FEAT-044f).
///
/// S'auto-masque pour tout compte n'ayant pas au moins le palier
/// [PlanLevel.pro] — [ProfilePage] l'insère donc sans condition (même
/// convention que `ProfileCrashReportingSection`).
///
/// Rendu selon [LandlordTierSnapshot] (`landlordTierProvider`) :
/// - `proStore` ∈ [mobileStores] → message info + bouton « Gérer dans {store} »
///   (FEAT-044e), sur le web comme dans les apps : il ouvre la page de gestion
///   du store D'ORIGINE de l'abonnement (URL RevenueCat, sinon page générique
///   du store). Ni Résilier, ni Réactiver, ni Changer d'offre : la résiliation
///   d'un achat intégré se fait chez le store, jamais via Stripe ;
/// - web (store `null`/inconnu inclus, cf. plan §R5 — ne jamais cacher le
///   chemin de résiliation à un abonné web) + `proWillRenew != false` →
///   « Actif — renouvellement le … » + bouton destructif « Résilier » →
///   dialog de confirmation (récapitulatif art. L215-1-1) ;
/// - web + `proWillRenew == false` → « Pro jusqu'au …, puis Gratuit » +
///   bouton « Réactiver » (pas de confirmation — action symétrique, non
///   destructive).
///
/// **Apps iOS/Android** ([isStoreApp]) : le statut et la résiliation d'un
/// abonnement web restent, mais « Réactiver » et « Changer d'offre »
/// disparaissent — reprendre une facturation Stripe ou changer d'offre depuis
/// une app store serait un achat hors achat intégré (App Store 3.1.1, règle
/// Paiements de Google Play).
class SubscriptionSection extends ConsumerWidget {
  const SubscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(landlordTierProvider).valueOrNull;
    if (!(snapshot?.plan.atLeast(PlanLevel.pro) ?? false)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final isBusy = ref.watch(manageSubscriptionControllerProvider).isLoading;
    final isMobileStore = mobileStores.contains(snapshot?.proStore);
    // Grandfathering I3 (FEAT-056) : `level` est non-null dès lors que
    // `atLeast(PlanLevel.pro)` a déjà validé l'accès à cette section (le
    // garde ci-dessus retourne `SizedBox.shrink()` sinon).
    final levelLabel = snapshot!.plan.level!.label(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.subscriptionSectionTitle(levelLabel)),
        const SizedBox(height: 8),
        if (isMobileStore) ...[
          Text(
            l10n.subscriptionManageOnStore,
            key: const Key('txt_subscription_manage_on_store'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('btn_subscription_manage_in_store'),
            onPressed: () => _openStoreManagement(ref, snapshot.proStore),
            child: Text(
              l10n.subscriptionManageInStoreButton(
                storeNameForProStore(snapshot.proStore),
              ),
            ),
          ),
        ] else if (snapshot.proWillRenew == false)
          ScheduledCancelView(
            expiresAt: snapshot.proExpiresAt,
            isBusy: isBusy,
            onReactivate: isStoreApp ? null : () => _reactivate(context, ref),
            levelLabel: levelLabel,
          )
        else
          ActiveSubscriptionView(
            expiresAt: snapshot.proExpiresAt,
            isBusy: isBusy,
            onCancel: () => _confirmCancel(context, ref),
          ),
        if (!isMobileStore && !isStoreApp) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('btn_subscription_change_plan'),
            onPressed: () => context.push('/pro'),
            child: Text(l10n.subscriptionChangePlanButton),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  /// Ouvre la page de gestion de l'abonnement du store D'ORIGINE : l'URL de
  /// RevenueCat si elle est connue, sinon la page générique du store. Aucun
  /// `context` ni `ref` après l'`await` ; un échec est journalisé, jamais
  /// propagé (le `onPressed` ne l'attend pas).
  Future<void> _openStoreManagement(WidgetRef ref, String? proStore) async {
    final service = ref.read(storeBillingServiceProvider);
    try {
      final uri =
          await service.managementUrl() ?? storeManagementFallbackUri(proStore);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _log.warning('Impossible d\'ouvrir la gestion de l\'abonnement : $uri');
      }
    } on Object catch (e, st) {
      _log.warning(
        'Ouverture de la gestion de l\'abonnement impossible',
        e,
        st,
      );
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final snapshot = ref.read(landlordTierProvider).valueOrNull;
    final expiresAt = snapshot?.proExpiresAt;
    // Fallback '—' (aligné sur les vues de statut) plutôt que '' : évite une
    // phrase tronquée « jusqu'au , puis… » dans le cas edge proExpiresAt == null.
    final dateLabel = expiresAt != null ? FrenchDate.format(expiresAt) : '—';
    final levelLabel = snapshot?.plan.level?.label(context) ?? '';

    final confirmed = await showSubscriptionCancelDialog(
      context,
      dateLabel: dateLabel,
      levelLabel: levelLabel,
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(manageSubscriptionControllerProvider.notifier)
        .cancel();
    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      ok: ok,
      successMessage: context.l10n.subscriptionCancelSuccess,
    );
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(manageSubscriptionControllerProvider.notifier)
        .reactivate();
    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      ok: ok,
      successMessage: context.l10n.subscriptionReactivateSuccess,
    );
  }

  void _showResult(
    BuildContext context,
    WidgetRef ref, {
    required bool ok,
    required String successMessage,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final message = ok
        ? successMessage
        : ref.read(manageSubscriptionControllerProvider).error
              is NoActiveWebSubscriptionException
        ? l10n.subscriptionErrorNoWebSub
        : l10n.subscriptionErrorGeneric;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: Key(
          ok ? 'snackbar_subscription_success' : 'snackbar_subscription_error',
        ),
        content: Text(message),
        backgroundColor: ok ? null : theme.colorScheme.errorContainer,
      ),
    );
  }
}

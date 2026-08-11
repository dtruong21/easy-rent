import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/cards/status_pill.dart';
import '../../../core/ui/cards/status_pill_tone.dart';
import '../../../core/utils/french_date.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/archive_confirm_dialog.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../../charge_regularization/presentation/widgets/charge_regularization_dialog.dart';
import '../../charge_regularization/presentation/widgets/charge_regularization_section.dart';
import '../../documents/presentation/widgets/documents_section.dart';
import '../../payments/presentation/widgets/payment_list_section.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../properties/application/property_detail_provider.dart';
import '../../receipts/presentation/receipts_list_section.dart';
import '../../tenants/application/tenant_detail_provider.dart';
import '../application/lease_detail_provider.dart';
import '../application/lease_form_controller.dart';
import '../application/leases_list_provider.dart';
import '../data/lease_repository.dart';
import '../domain/lease.dart';
import '../domain/lease_form_state.dart';
import '../domain/lease_status.dart';
import '../domain/lease_submit_error.dart';
import 'lease_submit_error_l10n.dart';
import 'lease_type_l10n.dart';
import 'widgets/close_lease_dialog.dart';

final _log = Logger('LeaseDetailPage');

/// Fiche lecture d'un bail.
///
/// Route : `/leases/:id` — accepte le query param optionnel
/// `?action=regularize` (raccourci FEAT-030 depuis la liste Baux, action
/// visible uniquement pour les baux en mode provisions, cf.
/// `Lease.canRegularizeCharges` — FEAT-042). Quand présent, la fiche ouvre
/// automatiquement le dialog de régularisation des charges une fois ses
/// données chargées (cf. [_LeaseDetailContent]).
///
/// Affiche toutes les informations + boutons "Modifier", "Clôturer" (si actif)
/// et "Archiver".
/// Section paiements : placeholder "Disponible après FEAT-006".
class LeaseDetailPage extends ConsumerWidget {
  const LeaseDetailPage({
    super.key,
    required this.id,
    this.openRegularizationOnLoad = false,
  });

  final String id;

  /// Vrai si la fiche doit ouvrir le dialog de régularisation dès que ses
  /// données sont chargées (raccourci `?action=regularize` résolu par
  /// `app_router.dart`). Si le chargement du bail échoue, le dialog ne
  /// s'ouvre jamais — on reste sur `_NotFoundPage` sans crash.
  final bool openRegularizationOnLoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLease = ref.watch(leaseDetailProvider(id));

    return asyncLease.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => const _NotFoundPage(),
      data: (lease) => _LeaseDetailContent(
        lease: lease,
        openRegularizationOnLoad: openRegularizationOnLoad,
      ),
    );
  }
}

/// Vue principale quand le bail est chargé.
class _LeaseDetailContent extends ConsumerStatefulWidget {
  const _LeaseDetailContent({
    required this.lease,
    this.openRegularizationOnLoad = false,
  });

  final Lease lease;
  final bool openRegularizationOnLoad;

  @override
  ConsumerState<_LeaseDetailContent> createState() =>
      _LeaseDetailContentState();
}

class _LeaseDetailContentState extends ConsumerState<_LeaseDetailContent> {
  /// Garde anti-ré-ouverture : le dialog de régularisation ne doit s'ouvrir
  /// qu'une seule fois par montage de la page, même si `build()` est
  /// ré-invoqué plusieurs fois (ex. changement des AsyncValue tenant/property
  /// /profile pendant que le bail reste chargé).
  bool _regularizationDialogOpened = false;

  Lease get lease => widget.lease;

  @override
  Widget build(BuildContext context) {
    // Écouter l'état du contrôleur de clôture pour les feedbacks.
    ref.listen<LeaseFormState>(leaseFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.leasesCloseSuccessSnackbar),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        },
        error: (msg) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LeaseSubmitError.fromCode(msg).message(context)),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        },
      );
    });

    // Charger le contexte nécessaire au bouton de partage des quittances.
    final asyncTenant = ref.watch(tenantDetailProvider(lease.tenantId));
    final asyncProperty = ref.watch(propertyDetailProvider(lease.propertyId));
    final asyncProfile = ref.watch(landlordProfileProvider);

    // Extraire les valeurs dès qu'elles sont disponibles — null sinon
    // (le bouton de partage se désactive gracieusement).
    final tenantEmail = asyncTenant.valueOrNull?.email;
    final tenantFirstName = asyncTenant.valueOrNull?.firstName ?? '';
    final tenantLastName = asyncTenant.valueOrNull?.lastName ?? '';
    final tenantFullName = '$tenantFirstName $tenantLastName'.trim();
    final propertyAddress = asyncProperty.valueOrNull?.address ?? '';
    final landlordFullName = asyncProfile.valueOrNull?.fullName ?? '';
    final landlordAddress = asyncProfile.valueOrNull?.address ?? '';

    // FEAT-028 : le retard est calculé au niveau de la liste (l'info
    // paiement n'est pas portée par le Lease seul). On réutilise le cache
    // de leasesListProvider — déjà chargé si l'utilisateur vient de
    // /leases — pour retrouver l'item correspondant sans dupliquer la
    // logique de calcul dans LeaseRepository.getById(). Défaut `false` si
    // absent (liste pas encore chargée, ou bail nouvellement créé).
    final leasesAsync = ref.watch(leasesListProvider);
    final isLate =
        leasesAsync.valueOrNull
            ?.firstWhereOrNull((item) => item.lease.id == lease.id)
            ?.isLate ??
        false;

    // Raccourci FEAT-030 (`?action=regularize` depuis la liste Baux) :
    // ouvrir le dialog de régularisation une fois cette frame posée, une
    // seule fois par montage (garde `_regularizationDialogOpened`). Le gate
    // légal (mode provisions uniquement, FEAT-042) est revérifié ici en plus
    // du gate déjà appliqué à la construction du raccourci dans la liste —
    // défense en profondeur si l'URL est partagée/tapée manuellement sur un
    // bail non éligible. `addPostFrameCallback` : on ne doit pas appeler
    // `showDialog` pendant `build()`.
    // Gate PRO (FEAT-044) en plus du gate légal : ce chemin deep-link
    // (`?openRegularization=1`) contourne la section, il doit donc appliquer la
    // même restriction — sinon un compte free atteindrait le dialog par URL.
    final hasChargeRegularizationForDeepLink = ref.watch(
      hasFeatureProvider(PlanFeature.chargeRegularization),
    );
    if (widget.openRegularizationOnLoad &&
        !_regularizationDialogOpened &&
        hasChargeRegularizationForDeepLink &&
        lease.canRegularizeCharges) {
      _regularizationDialogOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          builder: (_) => ChargeRegularizationDialog(
            leaseId: lease.id,
            propertyId: lease.propertyId,
            landlordFullName: landlordFullName,
            landlordAddress: landlordAddress,
            tenantFullName: tenantFullName,
            tenantFirstName: tenantFirstName,
            propertyAddress: propertyAddress,
            tenantEmail: tenantEmail,
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppAppBar(
        title: context.l10n.leasesDetailTitle,
        fallbackRoute: '/leases',
        actions: [
          IconButton(
            key: const Key('btn_edit_lease'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.l10n.commonEdit,
            onPressed: () => context.push('/leases/${lease.id}/edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(lease: lease, isLate: isLate),
            const SizedBox(height: 16),
            // FEAT-030 : remontée juste après le statut — la régularisation
            // des charges était auparavant enterrée après _InfoCard (3ᵉ
            // carte), peu visible pour qui arrive par navigation normale
            // (pas via le raccourci liste ci-dessus).
            ChargeRegularizationSection(
              lease: lease,
              landlordFullName: landlordFullName,
              landlordAddress: landlordAddress,
              tenantFullName: tenantFullName,
              tenantFirstName: tenantFirstName,
              propertyAddress: propertyAddress,
              tenantEmail: tenantEmail,
            ),
            const SizedBox(height: 16),
            _InfoCard(lease: lease),
            const SizedBox(height: 16),
            PaymentListSection(leaseId: lease.id),
            const SizedBox(height: 16),
            ReceiptsListSection(leaseId: lease.id),
            const SizedBox(height: 16),
            DocumentsSection(leaseId: lease.id),
            const SizedBox(height: 32),

            // Bouton Clôturer (uniquement si bail actif)
            if (lease.isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  key: const Key('btn_close_lease'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  icon: const Icon(Icons.do_not_disturb_outlined),
                  label: Text(context.l10n.leasesCloseButton),
                  onPressed: () => _showCloseDialog(context, ref),
                ),
              ),

            // Bouton Archiver
            OutlinedButton.icon(
              key: const Key('btn_archive_lease'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: Text(context.l10n.leasesArchiveButton),
              onPressed: () => _confirmArchive(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => CloseLeaseDialog(
        onClose: (effectiveEndDate) => ref
            .read(leaseFormControllerProvider.notifier)
            .close(leaseId: lease.id, effectiveEndDate: effectiveEndDate),
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: l10n.leasesArchiveDialogTitle,
        entityLabel: l10n.leasesArchiveDialogEntityLabel,
        standardMessage: l10n.leasesArchiveDialogStandardMessage,
        activeLeaseMessage: l10n.leasesArchiveDialogActiveLeaseMessage,
        hasActiveLease: lease.isActive,
        onConfirm: () => _archive(context, ref),
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    try {
      await ref.read(leaseRepositoryProvider).archive(lease.id);
      ref.invalidate(leasesListProvider);
      ref.invalidate(leaseDetailProvider(lease.id));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.leasesArchiveSuccessSnackbar),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
      context.go('/leases');
    } catch (e, st) {
      _log.severe('archive lease failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.leasesArchiveErrorSnackbar),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }
}

/// Card statut du bail.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.lease, this.isLate = false});

  final Lease lease;

  /// Vrai si le bail est en retard de paiement (FEAT-028). Prime sur le
  /// statut `active` standard — priorité la plus haute, cf.
  /// `lease_status_mapper.dart::leaseStatusPill`.
  final bool isLate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final (label, tone) = switch (lease.status) {
      // Réutilise `leasesFilterLate` (valeur FR identique "En retard") — pas
      // de duplication de clé, cf. `lease_status_mapper.dart`.
      LeaseStatus.active when isLate => (
        l10n.leasesFilterLate,
        StatusPillTone.danger,
      ),
      LeaseStatus.active => (l10n.leasesStatusActive, StatusPillTone.success),
      LeaseStatus.terminated => (
        l10n.leasesStatusTerminated,
        StatusPillTone.neutral,
      ),
      LeaseStatus.archived => (
        l10n.leasesStatusArchived,
        StatusPillTone.neutral,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              l10n.leasesDetailStatusLabel,
              style: theme.textTheme.titleMedium,
            ),
            const Spacer(),
            StatusPill(label: label, tone: tone),
          ],
        ),
      ),
    );
  }
}

/// Card d'informations du bail (lecture seule).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.lease});

  final Lease lease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bien lié — lien cliquable
            _LinkRow(
              icon: Icons.home_outlined,
              label: l10n.leasesDetailPropertyLabel,
              onTap: () => context.go('/properties/${lease.propertyId}'),
            ),
            const Divider(height: 24),

            // Locataire lié — lien cliquable
            _LinkRow(
              icon: Icons.person_outline,
              label: l10n.leasesDetailTenantLabel,
              onTap: () => context.go('/tenants/${lease.tenantId}'),
            ),

            // --- Type et durée ---
            const Divider(height: 24),
            Text(
              l10n.leasesDetailTypeAndDurationSection,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.description_outlined,
              label: l10n.leasesDetailLeaseTypeLabel,
              value: lease.leaseType.label(context),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: l10n.leasesDetailStartDateLabel,
              value: FrenchDate.format(lease.startDate),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.event_outlined,
              label: l10n.leasesDetailEndDateLabel,
              value: lease.endDate != null
                  ? FrenchDate.format(lease.endDate!)
                  : l10n.leasesOpenEndedAbbreviation,
            ),

            // --- Loyer et charges ---
            const Divider(height: 24),
            Text(
              l10n.leasesDetailRentAndChargesSection,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.euro_outlined,
              label: l10n.leasesDetailRentExclChargesLabel,
              value: MoneyFormat.formatEurosFromCents(lease.rentAmountCents),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.add_circle_outline,
              label: l10n.leasesDetailRecoverableChargesLabel,
              value: MoneyFormat.formatEurosFromCents(
                lease.recoverableChargesCents,
              ),
            ),
            const Divider(height: 24),
            // FEAT-036 : toujours affichée (même à 0) pour lever
            // l'ambiguïté — un 0 masqué pourrait être lu comme une donnée
            // manquante plutôt qu'une absence réelle de charge bailleur.
            _InfoRow(
              icon: Icons.remove_circle_outline,
              label: l10n.leasesDetailNonRecoverableChargesLabel,
              value: MoneyFormat.formatEurosFromCents(
                lease.nonRecoverableChargesCents,
              ),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.calculate_outlined,
              label: l10n.leasesDetailTotalChargesLabel,
              value: MoneyFormat.formatEurosFromCents(lease.totalChargesCents),
            ),
            const Divider(height: 24),
            // Loyer réellement dû par le locataire (rent + récupérable) —
            // INCHANGÉ par FEAT-036, ne doit PAS inclure le non-récupérable.
            _InfoRow(
              icon: Icons.euro,
              label: l10n.leasesDetailRentInclChargesLabel,
              value: MoneyFormat.formatEurosFromCents(lease.totalAmountCents),
            ),
            if (lease.depositAmountCents != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.lock_outline,
                label: l10n.leasesDetailDepositLabel,
                value: MoneyFormat.formatEurosFromCents(
                  lease.depositAmountCents!,
                ),
              ),
            ],
            if (lease.agencyFeesCents > 0) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.real_estate_agent_outlined,
                label: l10n.leasesDetailAgencyFeesLabel,
                value: MoneyFormat.formatEurosFromCents(lease.agencyFeesCents),
              ),
            ],

            // --- Modalités de paiement ---
            const Divider(height: 24),
            Text(
              l10n.leasesDetailPaymentTermsSection,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.event_repeat_outlined,
              label: l10n.leasesDetailPaymentDayLabel,
              value: l10n.leasesDetailPaymentDayValue(lease.paymentDay),
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.payment_outlined,
              label: l10n.leasesDetailPaymentMethodLabel,
              value: lease.paymentMethod.label,
            ),

            // --- IRL et clauses ---
            if (lease.irlIndexValue != null ||
                lease.irlQuarterRef != null ||
                lease.solidarityClause ||
                lease.entryInventoryDone) ...[
              const Divider(height: 24),
              Text(
                l10n.leasesDetailIrlAndClausesSection,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (lease.irlIndexValue != null) ...[
                _InfoRow(
                  icon: Icons.trending_up_outlined,
                  label: l10n.leasesDetailIrlIndexLabel,
                  value: '${lease.irlIndexValue}',
                ),
              ],
              if (lease.irlQuarterRef != null &&
                  lease.irlQuarterRef!.isNotEmpty) ...[
                const Divider(height: 24),
                _InfoRow(
                  icon: Icons.date_range_outlined,
                  label: l10n.leasesDetailIrlQuarterLabel,
                  value: lease.irlQuarterRef!,
                ),
              ],
              if (lease.solidarityClause) ...[
                const Divider(height: 24),
                _BadgeRow(
                  icon: Icons.handshake_outlined,
                  label: l10n.leasesDetailSolidarityClauseLabel,
                  badge: StatusPill(
                    label: l10n.leasesDetailSolidarityBadge,
                    tone: StatusPillTone.info,
                  ),
                ),
              ],
              if (lease.entryInventoryDone) ...[
                const Divider(height: 24),
                _BadgeRow(
                  icon: Icons.checklist_outlined,
                  label: l10n.leasesDetailEntryInventoryLabel,
                  badge: StatusPill(
                    label: l10n.leasesDetailEntryInventoryBadge,
                    tone: StatusPillTone.success,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Ligne avec un badge [StatusPill] à droite.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.icon,
    required this.label,
    required this.badge,
  });

  final IconData icon;
  final String label;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        badge,
      ],
    );
  }
}

/// Ligne avec un lien cliquable (pour bien et locataire).
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.leasesDetailViewSheetLink,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// Page "Bail introuvable" — affichée quand les Firestore Rules ne renvoient aucun document.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppAppBar(
        title: l10n.leasesDetailNotFoundAppBarTitle,
        fallbackRoute: '/leases',
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 80,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.leasesDetailNotFoundTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.leasesDetailNotFoundMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/leases'),
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.leasesDetailBackToListButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

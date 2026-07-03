import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/cards/card_empty_state.dart';
import '../../../core/ui/cards/view_mode.dart';
import '../../../core/ui/cards/view_mode_provider.dart';
import '../../../core/ui/breakpoints.dart';
import '../application/leases_filter_provider.dart';
import '../application/leases_list_provider.dart';
import '../domain/lease_filter.dart';
import 'widgets/leases_card_view.dart';
import 'widgets/leases_filter_bar.dart';
import 'widgets/leases_table_view.dart';

/// Liste des baux du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les baux avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun bail enregistré" + bouton "Créer un bail".
/// - Triés par `status ASC` (actif d'abord) puis `start_date DESC`.
/// - Bandeau si la limite de 200 baux est atteinte.
/// - Toggle Card/Tableau (masqué sur mobile).
/// - Filtre par statut (SegmentedButton sur desktop, Dropdown sur mobile).
class LeasesListPage extends ConsumerStatefulWidget {
  const LeasesListPage({super.key, this.initialFilter});

  /// Filtre pré-appliqué à l'arrivée (drill-down depuis un KPI dashboard,
  /// ex. `/leases?filter=renewable`). Appliqué une fois au montage ; `null`
  /// → la page garde le filtre courant du [leaseFilterProvider].
  final LeaseFilter? initialFilter;

  @override
  ConsumerState<LeasesListPage> createState() => _LeasesListPageState();
}

class _LeasesListPageState extends ConsumerState<LeasesListPage> {
  @override
  void initState() {
    super.initState();
    _applyInitialFilter(oldFilter: null);
  }

  @override
  void didUpdateWidget(covariant LeasesListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GoRouter réutilise ce State quand on re-navigue vers /leases (pageKey
    // identique quels que soient les query params) : initState ne rejoue
    // pas, un nouveau ?filter= (ex. retour du formulaire de création avec
    // ?filter=all) arrive ici.
    _applyInitialFilter(oldFilter: oldWidget.initialFilter);
  }

  void _applyInitialFilter({required LeaseFilter? oldFilter}) {
    final filter = widget.initialFilter;
    if (filter == null || filter == oldFilter) return;
    // Post-frame : muter un provider pendant le build est interdit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(leaseFilterProvider.notifier).state = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncLeases = ref.watch(filteredLeasesProvider);
    final viewMode = context.isMobile
        ? ViewMode.card
        : ref.watch(viewModeProvider('leases'));

    return Scaffold(
      appBar: AppAppBar(title: 'Mes baux', showBackButton: false),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_lease'),
        onPressed: () => context.push('/leases/new'),
        icon: const Icon(Icons.add),
        label: const Text('Créer un bail'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LeasesFilterBar(),
          Expanded(
            child: asyncLeases.when(
              loading: () => viewMode == ViewMode.table
                  ? LeasesTableView.loading()
                  : LeasesCardView.loading(),
              error: (e, _) => _ErrorView(
                message: e is FirebaseException
                    ? ("Erreur. Vérifiez votre connexion et réessayez.")
                    : 'Erreur de chargement',
                // Invalider la RACINE : le dérivé filtré relirait l'AsyncError
                // caché par le notifier sans jamais refetcher.
                onRetry: () => ref.invalidate(leasesListProvider),
              ),
              data: (leases) {
                if (leases.isEmpty) {
                  final filter = ref.watch(leaseFilterProvider);
                  final hasAnyLease =
                      ref.watch(leasesListProvider).valueOrNull?.isNotEmpty ??
                      false;
                  // Des baux existent mais le filtre les masque tous : le
                  // dire explicitement — « Aucun bail enregistré » mentirait
                  // (ex. bail créé invisible derrière un filtre
                  // « À renouveler » hérité d'un KPI dashboard).
                  if (hasAnyLease && filter != LeaseFilter.all) {
                    return CardEmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'Aucun bail pour ce filtre',
                      message:
                          'Le filtre « ${filter.labelFr} » ne correspond '
                          'à aucun de vos baux.',
                      action: OutlinedButton.icon(
                        key: const Key('btn_show_all_leases'),
                        onPressed: () =>
                            ref.read(leaseFilterProvider.notifier).state =
                                LeaseFilter.all,
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('Afficher tous les baux'),
                      ),
                    );
                  }
                  return CardEmptyState(
                    icon: Icons.description_outlined,
                    title: 'Aucun bail enregistré',
                    message:
                        'Créez un bail pour démarrer la gestion locative.\n'
                        "Vous aurez besoin d'au moins un bien et un locataire.",
                    action: FilledButton.icon(
                      key: const Key('btn_add_lease_empty'),
                      onPressed: () => context.push('/leases/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Créer un bail'),
                    ),
                  );
                }

                if (viewMode == ViewMode.table) {
                  return LeasesTableView(leases: leases);
                }

                return LeasesCardView(leases: leases);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger vos baux.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

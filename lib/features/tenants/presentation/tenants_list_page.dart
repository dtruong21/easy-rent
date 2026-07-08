import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/breakpoints.dart';
import '../../../core/ui/cards/card_empty_state.dart';
import '../../../core/ui/cards/view_mode.dart';
import '../../../core/ui/cards/view_mode_provider.dart';
import '../application/tenants_filter_provider.dart';
import '../application/tenants_list_provider.dart';
import 'widgets/tenants_card_view.dart';
import 'widgets/tenants_filter_bar.dart';
import 'widgets/tenants_table_view.dart';

/// Liste des locataires du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les locataires avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun locataire enregistré" + bouton "Ajouter un locataire".
/// - Triés par `last_name ASC, first_name ASC`.
/// - Bandeau si la limite de 200 locataires est atteinte.
/// - Toggle Card/Tableau (masqué sur mobile).
/// - Filtre par statut (SegmentedButton sur desktop, Dropdown sur mobile).
class TenantsListPage extends ConsumerWidget {
  const TenantsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final asyncTenants = ref.watch(filteredTenantsProvider);
    final viewMode = context.isMobile
        ? ViewMode.card
        : ref.watch(viewModeProvider('tenants'));

    return Scaffold(
      appBar: AppAppBar(title: l10n.tenantsListTitle, showBackButton: false),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_tenant'),
        onPressed: () => context.push('/tenants/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.tenantsAddButton),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TenantsFilterBar(),
          Expanded(
            child: asyncTenants.when(
              loading: () => viewMode == ViewMode.table
                  ? TenantsTableView.loading()
                  : TenantsCardView.loading(),
              error: (e, _) => _ErrorView(
                message: e is FirebaseException
                    ? l10n.tenantsErrorFirestore(e.message ?? e.code)
                    : l10n.tenantsErrorLoading,
                // Invalider la RACINE : le dérivé filtré relirait l'AsyncError
                // caché par le notifier sans jamais refetcher.
                onRetry: () => ref.invalidate(tenantsListItemsProvider),
              ),
              data: (tenants) {
                if (tenants.isEmpty) {
                  return CardEmptyState(
                    icon: Icons.people_outline,
                    title: l10n.tenantsEmptyTitle,
                    message: l10n.tenantsEmptyMessage,
                    action: FilledButton.icon(
                      key: const Key('btn_add_tenant_empty'),
                      onPressed: () => context.push('/tenants/new'),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.tenantsAddButton),
                    ),
                  );
                }

                // Bandeau limite 200 — affiché dans les deux vues via ce wrapper.
                final atLimit = tenants.length >= 200;

                if (viewMode == ViewMode.table) {
                  return _WithLimitBanner(
                    atLimit: atLimit,
                    child: TenantsTableView(tenants: tenants),
                  );
                }

                return _WithLimitBanner(
                  atLimit: atLimit,
                  child: TenantsCardView(tenants: tenants),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bandeau limite 200
// ---------------------------------------------------------------------------

class _WithLimitBanner extends StatelessWidget {
  const _WithLimitBanner({required this.child, required this.atLimit});

  final Widget child;
  final bool atLimit;

  @override
  Widget build(BuildContext context) {
    if (!atLimit) return child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            context.l10n.tenantsLimitReachedBanner,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
        Expanded(child: child),
      ],
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
              context.l10n.tenantsErrorLoadFailedTitle,
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
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

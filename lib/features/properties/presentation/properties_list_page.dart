import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/cards/card_empty_state.dart';
import '../../../core/ui/cards/view_mode.dart';
import '../../../core/ui/cards/view_mode_provider.dart';
import '../../../core/ui/breakpoints.dart';
import '../application/properties_filter_provider.dart';
import '../application/properties_list_provider.dart';
import 'widgets/properties_card_view.dart';
import 'widgets/properties_filter_bar.dart';
import 'widgets/properties_table_view.dart';

/// Liste des biens immobiliers du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les biens avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun bien enregistré" + bouton "Ajouter un bien".
/// - Triés par `created_at DESC`.
/// - Bandeau si la limite de 200 biens est atteinte.
/// - Toggle Card/Tableau (masqué sur mobile).
/// - Filtre par occupation (SegmentedButton sur desktop, Dropdown sur mobile).
class PropertiesListPage extends ConsumerWidget {
  const PropertiesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperties = ref.watch(filteredPropertiesProvider);
    final viewMode = context.isMobile
        ? ViewMode.card
        : ref.watch(viewModeProvider('properties'));

    return Scaffold(
      appBar: AppAppBar(title: 'Mes biens', fallbackRoute: '/dashboard'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_property'),
        onPressed: () => context.push('/properties/new'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un bien'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PropertiesFilterBar(),
          Expanded(
            child: asyncProperties.when(
              loading: () => viewMode == ViewMode.table
                  ? PropertiesTableView.loading()
                  : PropertiesCardView.loading(),
              error: (e, _) => _ErrorView(
                message: e is FirebaseException
                    ? ("Erreur. Vérifiez votre connexion et réessayez.")
                    : 'Erreur de chargement',
                // Invalider la RACINE : filteredPropertiesProvider n'est
                // qu'un dérivé — l'invalider seul relisait l'AsyncError
                // caché par le notifier sans jamais refetcher.
                onRetry: () => ref.invalidate(propertiesListItemsProvider),
              ),
              data: (properties) {
                if (properties.isEmpty) {
                  return CardEmptyState(
                    icon: Icons.home_outlined,
                    title: 'Aucun bien enregistré',
                    message:
                        'Ajoutez votre premier bien pour démarrer la gestion locative.\n'
                        'Vous pourrez ensuite y associer des locataires et des baux.',
                    action: FilledButton.icon(
                      key: const Key('btn_add_property_empty'),
                      onPressed: () => context.push('/properties/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un bien'),
                    ),
                  );
                }

                // Bandeau limite 200 — affiché dans les deux vues via ce wrapper.
                final atLimit = properties.length >= 200;

                if (viewMode == ViewMode.table) {
                  return _WithLimitBanner(
                    atLimit: atLimit,
                    child: PropertiesTableView(properties: properties),
                  );
                }

                return _WithLimitBanner(
                  atLimit: atLimit,
                  child: PropertiesCardView(properties: properties),
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
            'Limite de 200 biens atteinte. Contactez le support pour augmenter cette limite.',
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
              'Impossible de charger vos biens.',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/postgrest_error_mapper.dart';
import '../application/properties_list_provider.dart';
import '../domain/property.dart';
import 'widgets/property_card.dart';

/// Liste des biens immobiliers du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les biens avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun bien enregistré" + bouton "Ajouter un bien".
/// - Triés par `created_at DESC`.
/// - Bandeau si la limite de 200 biens est atteinte.
class PropertiesListPage extends ConsumerWidget {
  const PropertiesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperties = ref.watch(propertiesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes biens'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_property'),
        onPressed: () => context.push('/properties/new'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un bien'),
      ),
      body: asyncProperties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e is PostgrestException
              ? mapPostgrestError(e)
              : 'Erreur de chargement',
          onRetry: () => ref.invalidate(propertiesListProvider),
        ),
        data: (properties) => _PropertiesList(properties: properties),
      ),
    );
  }
}

class _PropertiesList extends StatelessWidget {
  const _PropertiesList({required this.properties});

  final List<Property> properties;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: properties.length + (properties.length >= 200 ? 1 : 0),
      itemBuilder: (context, index) {
        // Bandeau limite 200
        if (index == properties.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Limite de 200 biens atteinte. Contactez le support pour augmenter cette limite.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        }
        final property = properties[index];
        return PropertyCard(
          key: ValueKey(property.id),
          property: property,
          onTap: () => context.push('/properties/${property.id}'),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun bien enregistré',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ajoutez votre premier bien pour commencer\nà gérer votre parc locatif.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('btn_add_property_empty'),
              onPressed: () => context.push('/properties/new'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un bien'),
            ),
          ],
        ),
      ),
    );
  }
}

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

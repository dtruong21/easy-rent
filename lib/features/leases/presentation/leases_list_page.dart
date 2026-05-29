import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/postgrest_error_mapper.dart';
import '../application/leases_list_provider.dart';
import '../domain/lease_list_item.dart';
import 'widgets/lease_card.dart';

/// Liste des baux du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les baux avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun bail enregistré" + bouton "Créer un bail".
/// - Triés par `status ASC` (actif d'abord) puis `start_date DESC`.
/// - Bandeau si la limite de 200 baux est atteinte.
class LeasesListPage extends ConsumerWidget {
  const LeasesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLeases = ref.watch(leasesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes baux'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_lease'),
        onPressed: () => context.push('/leases/new'),
        icon: const Icon(Icons.add),
        label: const Text('Créer un bail'),
      ),
      body: asyncLeases.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e is PostgrestException
              ? mapPostgrestError(e)
              : 'Erreur de chargement',
          onRetry: () => ref.invalidate(leasesListProvider),
        ),
        data: (leases) => _LeasesList(leases: leases),
      ),
    );
  }
}

class _LeasesList extends StatelessWidget {
  const _LeasesList({required this.leases});

  final List<LeaseListItem> leases;

  @override
  Widget build(BuildContext context) {
    if (leases.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: leases.length + (leases.length >= 200 ? 1 : 0),
      itemBuilder: (context, index) {
        // Bandeau limite 200
        if (index == leases.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Limite de 200 baux atteinte. Contactez le support pour augmenter cette limite.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        }
        final item = leases[index];
        return LeaseCard(
          key: ValueKey(item.lease.id),
          item: item,
          onTap: () => context.push('/leases/${item.lease.id}'),
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
              Icons.description_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun bail enregistré',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Créez votre premier bail pour commencer\nà gérer vos contrats de location.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('btn_add_lease_empty'),
              onPressed: () => context.push('/leases/new'),
              icon: const Icon(Icons.add),
              label: const Text('Créer un bail'),
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

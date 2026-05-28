import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/postgrest_error_mapper.dart';
import '../application/tenants_list_provider.dart';
import '../domain/tenant.dart';
import 'widgets/tenant_card.dart';

/// Liste des locataires du landlord courant.
///
/// Critères Gherkin :
/// - Affiche uniquement les locataires avec `deleted_at IS NULL` (géré par RLS).
/// - État vide : "Aucun locataire enregistré" + bouton "Ajouter un locataire".
/// - Triés par `last_name ASC, first_name ASC`.
/// - Bandeau si la limite de 200 locataires est atteinte.
class TenantsListPage extends ConsumerWidget {
  const TenantsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTenants = ref.watch(tenantsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes locataires'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_add_tenant'),
        onPressed: () => context.push('/tenants/new'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un locataire'),
      ),
      body: asyncTenants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e is PostgrestException
              ? mapPostgrestError(e)
              : 'Erreur de chargement',
          onRetry: () => ref.invalidate(tenantsListProvider),
        ),
        data: (tenants) => _TenantsList(tenants: tenants),
      ),
    );
  }
}

class _TenantsList extends StatelessWidget {
  const _TenantsList({required this.tenants});

  final List<Tenant> tenants;

  @override
  Widget build(BuildContext context) {
    if (tenants.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: tenants.length + (tenants.length >= 200 ? 1 : 0),
      itemBuilder: (context, index) {
        // Bandeau limite 200
        if (index == tenants.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Limite de 200 locataires atteinte. Contactez le support pour augmenter cette limite.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        }
        final tenant = tenants[index];
        return TenantCard(
          key: ValueKey(tenant.id),
          tenant: tenant,
          onTap: () => context.push('/tenants/${tenant.id}'),
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
              Icons.people_outline,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun locataire enregistré',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ajoutez votre premier locataire pour commencer\nà gérer votre annuaire.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('btn_add_tenant_empty'),
              onPressed: () => context.push('/tenants/new'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un locataire'),
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
              'Impossible de charger vos locataires.',
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

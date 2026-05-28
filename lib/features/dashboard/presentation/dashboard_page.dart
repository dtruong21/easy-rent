import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';

/// Dashboard principal — hub de navigation EasyRent.
///
/// Chaque section est une [ListTile] dans le body.
/// Pas de drawer pour le MVP (cf. décision Q10 de FEAT-003).
/// À enrichir avec "Mes locataires" (FEAT-004), "Mes baux" (FEAT-005), etc.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyRent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Tableau de bord',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          ListTile(
            key: const Key('tile_properties'),
            leading: const Icon(Icons.home_outlined),
            title: const Text('Mes biens'),
            subtitle: const Text('Gérer votre parc immobilier'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/properties'),
          ),
          const Divider(indent: 16, endIndent: 16),
          // Futures sections (FEAT-004, FEAT-005…)
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Mes locataires'),
            subtitle: const Text('Disponible prochainement'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Mes baux'),
            subtitle: const Text('Disponible prochainement'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
          ),
        ],
      ),
    );
  }
}

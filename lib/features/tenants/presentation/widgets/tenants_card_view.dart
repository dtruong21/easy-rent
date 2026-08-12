import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/card_grid.dart';
import '../../../../core/ui/cards/card_skeleton.dart';
import '../../domain/tenant_list_item.dart';
import 'tenant_card.dart';

/// Vue en grille de cartes pour la liste des locataires.
///
/// Délègue à [CardGrid.builder] pour la virtualisation.
/// Affiche 6 [CardSkeleton] pendant le chargement.
class TenantsCardView extends StatelessWidget {
  const TenantsCardView({super.key, required this.tenants});

  final List<TenantListItem> tenants;

  /// Vue squelette de chargement (6 placeholders).
  static Widget loading() => const _TenantsCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 208,
      itemCount: tenants.length,
      itemBuilder: (context, index) {
        final item = tenants[index];
        return TenantCard(
          key: ValueKey(item.tenant.id),
          item: item,
          onTap: () => context.push('/tenants/${item.tenant.id}'),
        );
      },
    );
  }
}

class _TenantsCardViewLoading extends StatelessWidget {
  const _TenantsCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 208,
      children: List.generate(6, (_) => const CardSkeleton()),
    );
  }
}

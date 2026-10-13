import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/card_grid.dart';
import '../../../../core/ui/cards/card_skeleton.dart';
import '../../domain/lease_list_item.dart';
import 'lease_card.dart';

/// Vue en grille de cartes pour la liste des baux.
///
/// Délègue à [CardGrid.builder] pour la virtualisation.
/// Affiche 6 [CardSkeleton] pendant le chargement.
class LeasesCardView extends StatelessWidget {
  const LeasesCardView({super.key, required this.leases});

  final List<LeaseListItem> leases;

  /// Vue squelette de chargement (6 placeholders).
  static Widget loading() => const _LeasesCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 124,
      itemCount: leases.length,
      itemBuilder: (context, index) {
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

class _LeasesCardViewLoading extends StatelessWidget {
  const _LeasesCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 124,
      children: List.generate(6, (_) => const CardSkeleton()),
    );
  }
}

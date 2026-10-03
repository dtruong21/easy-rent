import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/card_grid.dart';
import '../../../../core/ui/cards/card_skeleton.dart';
import '../../domain/property_list_item.dart';
import 'property_card.dart';

/// Vue en grille de cartes pour la liste des biens immobiliers.
///
/// Délègue à [CardGrid.builder] pour la virtualisation.
/// Affiche 6 [CardSkeleton] pendant le chargement.
class PropertiesCardView extends StatelessWidget {
  const PropertiesCardView({super.key, required this.properties});

  final List<PropertyListItem> properties;

  /// Vue squelette de chargement (6 placeholders).
  static Widget loading() => const _PropertiesCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 124,
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final item = properties[index];
        return PropertyCard(
          key: ValueKey(item.property.id),
          item: item,
          onTap: () => context.push('/properties/${item.property.id}'),
        );
      },
    );
  }
}

class _PropertiesCardViewLoading extends StatelessWidget {
  const _PropertiesCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 124,
      children: List.generate(6, (_) => const CardSkeleton()),
    );
  }
}

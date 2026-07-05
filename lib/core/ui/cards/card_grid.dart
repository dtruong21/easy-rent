import 'package:flutter/material.dart';

/// Grille responsive pour afficher des [EntityCard].
///
/// Utilise [GridView.builder] avec [SliverGridDelegateWithMaxCrossAxisExtent]
/// pour adapter automatiquement le nombre de colonnes à la largeur disponible.
///
/// Exemple standard :
/// ```dart
/// CardGrid(
///   children: leases.map((l) => LeaseCard(lease: l)).toList(),
/// )
/// ```
///
/// Exemple avec virtualisation pour grandes listes :
/// ```dart
/// CardGrid.builder(
///   itemCount: leases.length,
///   itemBuilder: (ctx, i) => LeaseCard(lease: leases[i]),
/// )
/// ```
class CardGrid extends StatelessWidget {
  /// Constructeur standard — liste de widgets pré-construits.
  const CardGrid({
    super.key,
    required this.children,
    this.gap = 16,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
  }) : itemCount = null,
       itemBuilder = null;

  /// Constructeur builder — virtualisation pour grandes listes.
  const CardGrid.builder({
    super.key,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    this.gap = 16,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
  }) : children = null;

  /// Widgets à afficher (constructeur standard).
  final List<Widget>? children;

  /// Nombre d'éléments (constructeur builder).
  final int? itemCount;

  /// Builder d'éléments (constructeur builder).
  final IndexedWidgetBuilder? itemBuilder;

  /// Espacement entre les cellules (horizontal et vertical).
  final double gap;

  /// Padding autour de la grille.
  final EdgeInsetsGeometry padding;

  /// Si `true`, la grille prend la hauteur minimale nécessaire.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 380,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      childAspectRatio: 1.4,
    );

    if (itemBuilder != null && itemCount != null) {
      return GridView.builder(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        gridDelegate: delegate,
        itemCount: itemCount,
        itemBuilder: itemBuilder!,
      );
    }

    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: delegate,
      itemCount: children!.length,
      itemBuilder: (context, index) => children![index],
    );
  }
}

import 'package:flutter/material.dart';

/// Grille responsive pour afficher des cartes de liste (`SummaryCard`).
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
    this.mainAxisExtent,
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
    this.mainAxisExtent,
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

  /// Hauteur fixe (px) des cellules en grille (2 colonnes et plus), si
  /// fournie. Ignorée en colonne unique, où chaque carte prend sa hauteur
  /// naturelle.
  ///
  /// Par défaut (`null`), la hauteur suit `childAspectRatio: 1.4` — sur les
  /// grandes largeurs de cellule (desktop), ce ratio laisse une zone vide
  /// sous des cartes au contenu compact (retour recette 2026-08). Les cartes
  /// d'entités (biens/baux/locataires/quittances) fournissent une hauteur
  /// fixe calibrée sur leur contenu réel plutôt que de dépendre de la
  /// largeur de cellule.
  ///
  /// La valeur est calibrée pour un texte à taille normale ; elle grandit
  /// avec la taille de texte d'accessibilité ([_textScaleFactor]) pour qu'un
  /// grand texte ne fasse pas déborder la carte de sa cellule.
  final double? mainAxisExtent;

  /// Taille de police de référence pour mesurer l'agrandissement du texte :
  /// la plus petite des cartes (légende du chiffre clé). Avec une mise à
  /// l'échelle non linéaire (Android 14+), les petites polices grandissent
  /// le plus — se caler dessus ne sous-estime jamais la hauteur nécessaire.
  static const double _referenceFontSize = 11;

  /// Largeur max d'une colonne de la grille.
  static const double maxCrossAxisExtent = 380;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final insets = padding.resolve(Directionality.of(context));
        final width = constraints.maxWidth - insets.horizontal;
        // Même calcul de colonnes que SliverGridDelegateWithMaxCrossAxisExtent.
        final columns = (width / (maxCrossAxisExtent + gap)).ceil();
        return columns <= 1
            ? _buildList()
            : _buildGrid(_textScaleFactor(MediaQuery.textScalerOf(context)));
      },
    );
  }

  /// Une seule colonne (mobile) : hauteur NATURELLE de chaque carte.
  ///
  /// La hauteur fixe [mainAxisExtent] n'a de sens qu'en grille, pour aligner
  /// les rangées. Appliquée à une colonne unique, elle laissait ~70 px de
  /// vide sous chaque carte (retour recette mobile 2026-09-28).
  Widget _buildList() {
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: itemCount ?? children!.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
      itemBuilder: itemBuilder ?? (context, index) => children![index],
    );
  }

  /// Facteur d'agrandissement du texte, jamais inférieur à 1 : un texte
  /// réduit garde la hauteur calibrée.
  static double _textScaleFactor(TextScaler scaler) {
    final factor = scaler.scale(_referenceFontSize) / _referenceFontSize;
    return factor < 1 ? 1 : factor;
  }

  Widget _buildGrid(double textScaleFactor) {
    final extent = mainAxisExtent == null
        ? null
        : mainAxisExtent! * textScaleFactor;
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      mainAxisExtent: extent,
      childAspectRatio: extent != null ? 1.0 : 1.4,
    );

    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: delegate,
      itemCount: itemCount ?? children!.length,
      itemBuilder: itemBuilder ?? (context, index) => children![index],
    );
  }
}

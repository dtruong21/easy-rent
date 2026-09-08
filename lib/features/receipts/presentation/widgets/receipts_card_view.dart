import 'package:flutter/material.dart';

import '../../../../core/ui/cards/card_grid.dart';
import '../../../../core/ui/cards/card_skeleton.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../domain/receipt.dart';
import 'receipt_card.dart';

/// Vue en grille de cartes pour les quittances.
///
/// Délègue à [CardGrid.builder] pour la virtualisation.
/// Affiche 6 [CardSkeleton] pendant le chargement.
/// Pas de groupement par année — tri DESC (hérité du repository).
class ReceiptsCardView extends StatelessWidget {
  const ReceiptsCardView({
    super.key,
    required this.receipts,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    this.propertyColorKey,
  });

  final List<Receipt> receipts;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  /// Couleur d'identité du bien lié — déjà résolue par l'appelant (cf.
  /// `ReceiptCard.propertyColorKey`).
  final PropertyColorKey? propertyColorKey;

  /// Vue squelette de chargement (6 placeholders).
  static Widget loading() => const _ReceiptsCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid.builder(
      key: const Key('receipts_card_grid'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 244,
      itemCount: receipts.length,
      itemBuilder: (context, index) {
        final receipt = receipts[index];
        return ReceiptCard(
          key: ValueKey(receipt.id),
          receipt: receipt,
          leaseId: leaseId,
          tenantEmail: tenantEmail,
          tenantFirstName: tenantFirstName,
          propertyAddress: propertyAddress,
          landlordFullName: landlordFullName,
          propertyColorKey: propertyColorKey,
        );
      },
    );
  }
}

class _ReceiptsCardViewLoading extends StatelessWidget {
  const _ReceiptsCardViewLoading();

  @override
  Widget build(BuildContext context) {
    return CardGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      mainAxisExtent: 244,
      children: List.generate(6, (_) => const CardSkeleton()),
    );
  }
}

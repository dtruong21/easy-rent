import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/dashboard_snapshot.dart';
import 'kpi_card.dart';

/// Grille responsive de 4 KPI cards.
///
/// Layout :
/// - >900 px : 4 colonnes
/// - 600–900 px : 2 colonnes
/// - <600 px : 1 colonne
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900
            ? 4
            : width > 600
            ? 2
            : 1;
        final ratio = width > 900 ? 1.8 : 1.6;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: ratio,
          crossAxisSpacing: spacing.md,
          mainAxisSpacing: spacing.md,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _buildCards(context),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final loyers = snapshot.loyers;
    final retards = snapshot.retards;
    final renouvellements = snapshot.renouvellements;
    final docs = snapshot.docs;

    // Couleur sémantique loyers.
    final loyersColor = loyers.encaissedCents < loyers.dueCents
        ? colors.danger.solid
        : colors.success.solid;

    // Couleur sémantique retards.
    final retardsColor = retards.count > 0
        ? colors.danger.solid
        : colors.neutral.solid;

    // Couleur sémantique renouvellements.
    final renouvellementsColor = renouvellements.count > 0
        ? colors.warning.solid
        : colors.neutral.solid;

    // Couleur sémantique docs.
    final docsColor = docs.count > 0 ? colors.info.solid : colors.neutral.solid;

    // Drill-down : chaque KPI (sauf Documents, faute de page globale) ouvre
    // la liste des baux pré-filtrée. Loyers mène aux baux actifs — c'est là
    // que vivent paiements et quittances. Retards mène désormais au filtre
    // dédié `late` (FEAT-028, LeaseListItem porte l'info paiement).
    // Renouvellements a un filtre exact (renewable).
    return [
      KpiCard(
        key: const Key('kpi_loyers'),
        icon: Icons.euro_outlined,
        label: 'Loyers du mois',
        value: MoneyFormat.formatEurosFromCents(loyers.encaissedCents),
        subtitle: 'Dû : ${MoneyFormat.formatEurosFromCents(loyers.dueCents)}',
        semanticColor: loyersColor,
        onTap: () => context.go('/leases?filter=active'),
      ),
      KpiCard(
        key: const Key('kpi_retards'),
        icon: Icons.warning_amber_outlined,
        label: 'Retards de paiement',
        value: retards.count.toString(),
        subtitle: retards.count > 0
            ? 'locataire(s) en retard'
            : 'Tout est à jour',
        semanticColor: retardsColor,
        onTap: () => context.go('/leases?filter=late'),
      ),
      KpiCard(
        key: const Key('kpi_renouvellements'),
        icon: Icons.event_outlined,
        label: 'Baux à renouveler',
        value: renouvellements.count.toString(),
        subtitle: 'dans les 30 prochains jours',
        semanticColor: renouvellementsColor,
        onTap: () => context.go('/leases?filter=renewable'),
      ),
      // Documents : pas de page globale documents (ils vivent sous
      // /leases/:id) → pas de drill-down (pas de onTap, donc pas de chevron).
      KpiCard(
        key: const Key('kpi_docs'),
        icon: Icons.folder_outlined,
        label: 'Documents en attente',
        value: docs.count.toString(),
        subtitle: 'catégorie "autre"',
        semanticColor: docsColor,
      ),
    ];
  }
}

import 'package:flutter/material.dart';

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
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _buildCards(context),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context) {
    final theme = Theme.of(context);
    final loyers = snapshot.loyers;
    final retards = snapshot.retards;
    final renouvellements = snapshot.renouvellements;
    final docs = snapshot.docs;

    // Couleur sémantique loyers.
    final loyersColor = loyers.encaissedCents < loyers.dueCents
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    // Couleur sémantique retards.
    final retardsColor = retards.count > 0
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    // Couleur sémantique renouvellements.
    final renouvellementsColor = renouvellements.count > 0
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;

    return [
      KpiCard(
        key: const Key('kpi_loyers'),
        icon: Icons.euro_outlined,
        label: 'Loyers du mois',
        value: MoneyFormat.formatEurosFromCents(loyers.encaissedCents),
        subtitle: 'Dû : ${MoneyFormat.formatEurosFromCents(loyers.dueCents)}',
        semanticColor: loyersColor,
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
      ),
      KpiCard(
        key: const Key('kpi_renouvellements'),
        icon: Icons.event_outlined,
        label: 'Baux à renouveler',
        value: renouvellements.count.toString(),
        subtitle: 'dans les 30 prochains jours',
        semanticColor: renouvellementsColor,
      ),
      KpiCard(
        key: const Key('kpi_docs'),
        icon: Icons.folder_outlined,
        label: 'Documents en attente',
        value: docs.count.toString(),
        subtitle: 'catégorie "autre"',
        semanticColor: theme.colorScheme.onSurfaceVariant,
      ),
    ];
  }
}

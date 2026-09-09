import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../properties/application/properties_list_provider.dart';

/// KPI patrimoniaux du dashboard, dérivés de la liste des biens
/// ([propertiesListItemsProvider]) — aucune requête propre.
class PortfolioKpis {
  const PortfolioKpis({
    required this.occupied,
    required this.total,
    required this.patrimoineCents,
    required this.propertiesWithPrice,
  });

  /// Nombre de biens avec un bail actif.
  final int occupied;

  /// Nombre total de biens.
  final int total;

  /// Somme des prix d'achat renseignés (centimes).
  final int patrimoineCents;

  /// Nombre de biens dont le prix d'achat est renseigné.
  final int propertiesWithPrice;

  bool get hasProperties => total > 0;
  int get vacant => total - occupied;

  /// `null` s'il n'y a aucun bien (pas de division par zéro).
  int? get occupancyPercent =>
      total == 0 ? null : ((occupied / total) * 100).round();

  bool get hasAnyPrice => propertiesWithPrice > 0;
}

/// Occupation + patrimoine, dérivés de [propertiesListItemsProvider].
///
/// `PropertyListItem` porte déjà `activeLeaseId` (occupation) et
/// `property.purchasePriceCents` (patrimoine) — donc zéro requête propre.
final dashboardPortfolioKpisProvider = Provider<AsyncValue<PortfolioKpis>>((
  ref,
) {
  final asyncItems = ref.watch(propertiesListItemsProvider);
  return asyncItems.whenData((items) {
    final occupied = items.where((i) => i.activeLeaseId != null).length;
    var patrimoine = 0;
    var withPrice = 0;
    for (final i in items) {
      final price = i.property.purchasePriceCents;
      if (price != null) {
        patrimoine += price;
        withPrice++;
      }
    }
    return PortfolioKpis(
      occupied: occupied,
      total: items.length,
      patrimoineCents: patrimoine,
      propertiesWithPrice: withPrice,
    );
  });
});

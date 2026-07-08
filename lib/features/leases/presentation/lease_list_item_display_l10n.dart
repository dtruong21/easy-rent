import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../data/lease_repository.dart';
import '../domain/lease_list_item.dart';

/// Résout les libellés affichables de [LeaseListItem] (FEAT-043).
///
/// [LeaseListItem.propertyName]/[LeaseListItem.tenantDisplayName] portent un
/// texte de repli FR en dur (`(bien archivé)` / `(locataire archivé)`, cf.
/// [FirestoreLeaseRepository.listForDisplay]) quand le bien/locataire lié a
/// été archivé entre-temps — ce sentinel est produit par la couche
/// `data/` (pas de `BuildContext` disponible là-bas) mais reste visible dans
/// l'UI (cartes, tableau). Cette extension le détecte et le remplace par la
/// chaîne localisée au moment du rendu, sans changer le contrat du modèle ni
/// casser les tests qui assertent directement sur le sentinel FR.
///
/// ⚠️ Couplée aux constantes exactes utilisées par le repository — si ce
/// texte de repli change côté `data/`, cette extension doit être mise à jour
/// en miroir.
extension LeaseListItemDisplayL10n on LeaseListItem {
  static const String _archivedPropertySentinel = '(bien archivé)';
  static const String _archivedTenantSentinel = '(locataire archivé)';

  String displayPropertyName(BuildContext context) {
    return propertyName == _archivedPropertySentinel
        ? context.l10n.leasesArchivedPropertyPlaceholder
        : propertyName;
  }

  String displayTenantName(BuildContext context) {
    return tenantDisplayName == _archivedTenantSentinel
        ? context.l10n.leasesArchivedTenantPlaceholder
        : tenantDisplayName;
  }
}

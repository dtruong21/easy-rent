import 'edl_enums.dart';
import 'etat_des_lieux.dart';

/// Pièces/éléments par défaut proposés à la création d'un EDL — évite la page
/// blanche. Entièrement éditable/supprimable par le bailleur. Condition par
/// défaut `bon` (l'usage : le bailleur ajuste ce qui diffère).
List<EdlRoom> defaultEdlRooms() {
  EdlElement e(String name) =>
      EdlElement(name: name, condition: EdlCondition.bon, comment: null);
  const surfaces = ['Sol', 'Murs', 'Plafond'];
  return [
    EdlRoom(name: 'Séjour', elements: [for (final s in surfaces) e(s)]),
    EdlRoom(name: 'Chambre', elements: [for (final s in surfaces) e(s)]),
    EdlRoom(
      name: 'Cuisine',
      elements: [for (final s in surfaces) e(s), e('Équipements')],
    ),
    EdlRoom(
      name: 'Salle de bain',
      elements: [for (final s in surfaces) e(s), e('Sanitaires')],
    ),
    EdlRoom(name: 'WC', elements: [for (final s in surfaces) e(s)]),
  ];
}

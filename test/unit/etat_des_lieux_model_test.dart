import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_default_template.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EtatDesLieuxType round-trip sqlValue', () {
    for (final t in EtatDesLieuxType.values) {
      expect(EtatDesLieuxType.fromSql(t.sqlValue), t);
    }
    expect(EtatDesLieuxType.entree.sqlValue, 'entree');
    expect(EtatDesLieuxType.sortie.sqlValue, 'sortie');
  });

  test('EdlCondition round-trip sqlValue', () {
    for (final c in EdlCondition.values) {
      expect(EdlCondition.fromSql(c.sqlValue), c);
    }
    expect(EdlCondition.neuf.sqlValue, 'neuf');
    expect(EdlCondition.mauvais.sqlValue, 'mauvais');
  });

  test('defaultEdlRooms fournit des pièces non vides avec éléments', () {
    final rooms = defaultEdlRooms();
    expect(rooms, isNotEmpty);
    expect(rooms.every((r) => r.elements.isNotEmpty), isTrue);
  });

  test('EtatDesLieux se construit avec ses champs', () {
    final edl = EtatDesLieux(
      id: 'e1',
      landlordId: 'l1',
      leaseId: 'lease1',
      type: EtatDesLieuxType.entree,
      date: DateTime(2026, 9, 16),
      propertyAddress: '1 rue X, 75001 Paris',
      landlordFullName: 'Jean Bailleur',
      landlordAddress: '10 rue du Bailleur, 75002 Paris',
      tenantFullName: 'Marie Locataire',
      rooms: const [
        EdlRoom(
          name: 'Séjour',
          elements: [
            EdlElement(
              name: 'Murs',
              condition: EdlCondition.bon,
              comment: null,
            ),
          ],
        ),
      ],
      meterReadings: const EdlMeterReadings(
        waterIndex: '123',
        electricityIndex: null,
        gasIndex: null,
      ),
      keysCount: 3,
      generalComment: null,
      createdAt: DateTime(2026, 9, 16),
    );
    expect(edl.rooms.single.elements.single.condition, EdlCondition.bon);
    expect(edl.keysCount, 3);
  });
}

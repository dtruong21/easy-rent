import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderEtatDesLieuxPdf produit des bytes non vides', () async {
    final edl = EtatDesLieux(
      id: 'e1',
      landlordId: 'l1',
      leaseId: 'lease1',
      type: EtatDesLieuxType.entree,
      date: DateTime(2026, 9, 16),
      propertyAddress: '1 rue X, 75001 Paris',
      landlordFullName: 'Jean Bailleur',
      tenantFullName: 'Marie Locataire',
      rooms: const [
        EdlRoom(
          name: 'Séjour',
          elements: [
            EdlElement(
              name: 'Murs',
              condition: EdlCondition.bon,
              comment: 'RAS',
            ),
          ],
        ),
      ],
      meterReadings: const EdlMeterReadings(
        waterIndex: '123',
        electricityIndex: '456',
        gasIndex: null,
      ),
      keysCount: 3,
      generalComment: null,
      createdAt: DateTime(2026, 9, 16),
    );
    final bytes = await renderEtatDesLieuxPdf(edl);
    expect(bytes, isNotEmpty);
  });
}

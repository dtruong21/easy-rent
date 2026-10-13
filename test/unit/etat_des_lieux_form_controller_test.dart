/// Tests unitaires de [EtatDesLieuxFormController] (FEAT-037).
///
/// Régression recette mobile 2026-09-28 : après une création, la liste des
/// EDL du bail (provider non autoDispose) n'était jamais rechargée — le
/// nouvel EDL n'apparaissait qu'après un redémarrage de l'app.
library;

import 'package:easyrent/features/etat_des_lieux/application/etat_des_lieux_form_controller.dart';
import 'package:easyrent/features/etat_des_lieux/application/etat_des_lieux_list_provider.dart';
import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_repository.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_default_template.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EtatDesLieux _edl(String id) => EtatDesLieux(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  type: EtatDesLieuxType.entree,
  date: DateTime(2026, 9, 28),
  propertyAddress: '1 rue du Test, 75000 Paris',
  landlordFullName: 'Jean Bailleur',
  landlordAddress: '2 rue du Bailleur, 75000 Paris',
  tenantFullName: 'Marie Locataire',
  rooms: const [],
  meterReadings: EdlMeterReadings(),
  keysCount: 2,
  createdAt: DateTime(2026, 9, 28),
);

class _FakeRepo implements EtatDesLieuxRepository {
  final List<EtatDesLieux> stored = [];
  int listCalls = 0;

  @override
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  }) async {
    final edl = _edl('edl-${stored.length + 1}');
    stored.add(edl);
    return edl;
  }

  @override
  Future<List<EtatDesLieux>> listForLease(String leaseId) async {
    listCalls++;
    return List.of(stored);
  }

  @override
  Future<EtatDesLieux> getById(String id) async =>
      stored.firstWhere((e) => e.id == id);
}

void main() {
  test('une création réussie recharge la liste des EDL du bail', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [etatDesLieuxRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    // La page liste est ouverte (et garde le provider vivant).
    final sub = container.listen(
      etatDesLieuxListProvider('lease-1'),
      (_, _) {},
    );
    addTearDown(sub.close);
    expect(
      await container.read(etatDesLieuxListProvider('lease-1').future),
      isEmpty,
    );

    // Le contrôleur est autoDispose : on le garde vivant le temps du submit.
    final ctrlSub = container.listen(
      etatDesLieuxFormControllerProvider,
      (_, _) {},
    );
    addTearDown(ctrlSub.close);
    await container
        .read(etatDesLieuxFormControllerProvider.notifier)
        .submit(
          leaseId: 'lease-1',
          type: EtatDesLieuxType.entree,
          date: DateTime(2026, 9, 28),
          rooms: defaultEdlRooms(),
          meterReadings: EdlMeterReadings(),
          keysCount: 2,
        );

    final list = await container.read(
      etatDesLieuxListProvider('lease-1').future,
    );
    expect(list.map((e) => e.id), ['edl-1']);
    expect(repo.listCalls, 2);
  });
}

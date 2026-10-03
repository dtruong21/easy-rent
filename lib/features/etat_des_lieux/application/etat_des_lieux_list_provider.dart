import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/etat_des_lieux_repository.dart';
import '../domain/etat_des_lieux.dart';

/// Liste des états des lieux d'un bail — patron `leaseReceiptsProvider`.
///
/// Vit dans `application/` (et non dans la page liste) pour que le contrôleur
/// de formulaire puisse l'invalider après une création : sans ça, la liste
/// (provider non autoDispose) restait figée sur son premier chargement et
/// n'affichait le nouvel EDL qu'après un redémarrage de l'app.
final etatDesLieuxListProvider =
    FutureProvider.family<List<EtatDesLieux>, String>((ref, leaseId) {
      return ref.watch(etatDesLieuxRepositoryProvider).listForLease(leaseId);
    });

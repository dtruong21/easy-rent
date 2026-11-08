import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('AccountExportRepository');

/// Export RGPD (droit à la portabilité, art. 20) : récupère l'intégralité
/// des données du compte via la Callable `exportAccountData` (Task 2).
///
/// Jamais d'accès Firestore direct côté client — la CF fait l'agrégation
/// côté serveur (isolation prod/staging, ADR 0003).
abstract interface class AccountExportRepository {
  Future<Map<String, dynamic>> exportAccountData();
}

class FirebaseAccountExportRepository implements AccountExportRepository {
  FirebaseAccountExportRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> exportAccountData() async {
    _log.info('exportAccountData()');
    final res = await _functions
        .httpsCallable(
          'exportAccountData',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call();
    return Map<String, dynamic>.from(res.data as Map);
  }
}

final accountExportRepositoryProvider = Provider<AccountExportRepository>((
  ref,
) {
  return FirebaseAccountExportRepository(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});

import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _log = Logger('EdgeFunctionErrorMapper');

/// Exception levée quand le profil bailleur est incomplet (422 profile_incomplete).
///
/// [missing] contient les champs manquants identifiés par l'Edge Function.
class ProfileIncompleteException implements Exception {
  const ProfileIncompleteException({required this.missing});

  final List<String> missing;

  @override
  String toString() =>
      'ProfileIncompleteException: champs manquants = $missing';
}

/// Traduit une [FunctionException] (Edge Function) en message utilisateur FR.
///
/// L'Edge Function `generate-receipt` retourne des codes HTTP standard :
/// - 401 : JWT absent / invalide
/// - 403 : paiements ou bail n'appartiennent pas au landlord
/// - 404 : bail ou paiements introuvables
/// - 422 : validation métier (profil incomplet, aucun paiement, etc.)
/// - 500 : erreur serveur (génération PDF, upload Storage)
///
/// Pour [status] == 422 avec `error == 'profile_incomplete'`, cette fonction
/// lève [ProfileIncompleteException] — le controller doit catcher ce cas
/// séparément pour passer en état [profileIncomplete].
String mapEdgeFunctionError(FunctionException e) {
  final status = e.status;
  final details = e.details;
  _log.warning('FunctionException status=$status details=$details');

  // 422 profile_incomplete → lever une exception spécifique pour le controller.
  if (status == 422) {
    if (details is Map<String, dynamic> &&
        details['error'] == 'profile_incomplete') {
      final missing = details['missing'];
      final missingList = missing is List
          ? missing.map((e) => e.toString()).toList()
          : <String>[];
      throw ProfileIncompleteException(missing: missingList);
    }
    // 422 autre (aucun paiement, dates incohérentes, etc.)
    if (details is Map<String, dynamic> && details['error'] != null) {
      final errCode = details['error'] as String;
      return switch (errCode) {
        'no_payments_found' =>
          'Aucun paiement trouvé pour cette période. Vérifiez les paiements enregistrés.',
        'payments_different_leases' =>
          'Les paiements sélectionnés appartiennent à des baux différents.',
        'inconsistent_dates' =>
          'Les dates de la période sont incohérentes (la date de fin doit être après la date de début).',
        _ => 'Données invalides. Vérifiez les informations et réessayez.',
      };
    }
    return 'Données invalides. Vérifiez les informations et réessayez.';
  }

  if (status == 401) {
    return 'Session expirée. Veuillez vous reconnecter.';
  }
  if (status == 403) {
    return "Vous n'avez pas les droits pour effectuer cette action.";
  }
  if (status == 404) {
    return 'Bail ou paiements introuvables. Rafraîchissez la page et réessayez.';
  }
  if (status == 500) {
    return 'Erreur lors de la génération du PDF. Veuillez réessayer.';
  }

  return 'Une erreur est survenue. Veuillez réessayer.';
}

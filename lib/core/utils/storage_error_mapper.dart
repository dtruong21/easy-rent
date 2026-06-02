import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _log = Logger('StorageErrorMapper');

/// Traduit une [StorageException] en message utilisateur français.
///
/// Utilisé par le repository de documents lors des erreurs d'upload Storage.
String mapStorageError(StorageException e) {
  _log.warning(
    'StorageException statusCode=${e.statusCode} message=${e.message}',
  );
  return switch (e.statusCode) {
    '413' => 'Fichier trop volumineux (max 10 Mo).',
    '415' => 'Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP.',
    '409' => 'Un fichier portant ce nom existe déjà.',
    '507' => 'Espace de stockage insuffisant.',
    _ => 'Erreur de stockage. Réessayez plus tard.',
  };
}

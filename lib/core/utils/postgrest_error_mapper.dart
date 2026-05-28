import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

final _log = Logger('PostgrestErrorMapper');

/// Traduit une [PostgrestException] en message utilisateur français.
///
/// En prod ([Env.isProd]), seul le code d'erreur est loggué — jamais le message
/// brut qui peut contenir des informations de schéma (table, contrainte, etc.).
/// Hors prod, le détail complet est inclus pour faciliter le débogage.
String mapPostgrestError(PostgrestException e) {
  final detail = Env.isProd ? '' : ' msg=${e.message}';
  _log.warning('PostgrestException code=${e.code}$detail');
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();

  // Violation de RLS (permission denied) — ne devrait pas arriver via l'UI normale.
  if (code == '42501' || msg.contains('permission denied')) {
    return "Vous n'avez pas les droits pour effectuer cette action.";
  }
  // Violation de contrainte CHECK (surface <= 0, type invalide, etc.).
  if (code == '23514' || msg.contains('check_violation')) {
    if (msg.contains('surface')) {
      return 'La surface doit être un nombre positif inférieur à 9999,99 m².';
    }
    if (msg.contains('type')) {
      return 'Type de bien invalide.';
    }
    return 'Données invalides. Vérifiez les champs et réessayez.';
  }
  // Violation de contrainte NOT NULL.
  if (code == '23502' || msg.contains('not_null_violation')) {
    return 'Un champ obligatoire est manquant.';
  }
  // Erreur réseau / timeout générique.
  if (msg.contains('network') || msg.contains('timeout')) {
    return 'Erreur réseau. Vérifiez votre connexion et réessayez.';
  }

  return 'Une erreur est survenue. Veuillez réessayer.';
}

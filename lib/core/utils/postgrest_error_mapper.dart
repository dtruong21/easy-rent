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
    // Documents — colonnes immuables protégées par trigger tr_01b
    if (msg.contains('immutable on documents')) {
      return 'Ces propriétés du document ne peuvent pas être modifiées.';
    }
    return "Vous n'avez pas les droits pour effectuer cette action.";
  }
  // RPC qui lève NOT FOUND : soft_delete_* cross-user ou ID inexistant.
  if (code == 'P0002' || msg.contains('no_data_found')) {
    // Documents — soft_delete_document : not found, not owned, or already deleted
    if (msg.contains('document not found') ||
        msg.contains('not owned') ||
        msg.contains('already deleted')) {
      return 'Document introuvable ou déjà supprimé.';
    }
    return 'Élément introuvable. Il a peut-être déjà été archivé.';
  }
  // Violation de contrainte CHECK (surface, dates, montants, etc.).
  if (code == '23514' || msg.contains('check_violation')) {
    // Trigger cross-FK ownership (leases / payments).
    if (msg.contains('ownership mismatch')) {
      return "Ce bail ne vous appartient pas.";
    }
    if (msg.contains('surface')) {
      return 'La surface doit être un nombre positif inférieur à 9999,99 m².';
    }
    if (msg.contains('type')) {
      return 'Type de bien invalide.';
    }
    if (msg.contains('rent_amount')) {
      return 'Le loyer doit être un montant positif.';
    }
    if (msg.contains('charges_amount')) {
      return 'Les charges ne peuvent pas être négatives.';
    }
    if (msg.contains('payment_method')) {
      return 'Mode de paiement invalide.';
    }
    if (msg.contains('period_end') || msg.contains('end_date')) {
      return 'La date de fin doit être postérieure à la date de début.';
    }
    if (msg.contains('date_range') ||
        msg.contains('period_start') ||
        msg.contains('paid_at') ||
        msg.contains('start_date')) {
      return 'Date hors plage autorisée (1900–2100).';
    }
    if (msg.contains('notes')) {
      return 'Les notes ne peuvent pas dépasser 500 caractères.';
    }
    // Documents — validation MIME whitelist (CHECK mime_type IN (...))
    if (msg.contains('mime_type')) {
      return 'Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP.';
    }
    // Documents — validation taille (CHECK size_bytes <= 10485760)
    if (msg.contains('size_bytes')) {
      return 'Ce fichier dépasse la limite de 10 Mo.';
    }
    // Documents — trigger ownership mismatch (bail non owned)
    if (msg.contains('document lease ownership mismatch')) {
      return "Le bail n'existe pas ou ne vous appartient pas.";
    }
    return 'Données invalides. Vérifiez les champs et réessayez.';
  }
  // Violation de contrainte NOT NULL.
  if (code == '23502' || msg.contains('not_null_violation')) {
    return 'Un champ obligatoire est manquant.';
  }
  // Violation de FK (lease_id → leases, landlord_id → landlords, etc.).
  if (code == '23503' || msg.contains('foreign_key_violation')) {
    return 'Élément lié introuvable. Rafraîchissez la page et réessayez.';
  }
  // Erreur réseau / timeout générique.
  if (msg.contains('network') || msg.contains('timeout')) {
    return 'Erreur réseau. Vérifiez votre connexion et réessayez.';
  }

  return 'Une erreur est survenue. Veuillez réessayer.';
}

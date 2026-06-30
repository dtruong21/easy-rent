import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';

final _log = Logger('ActiveLeaseProvider');

/// Retourne le loyer HC (hors charges) du bail actif pour un bien donné,
/// ou null si le bien est vacant.
///
/// Interroge directement la table `leases` avec un filtre sur property_id,
/// status='active' et deleted_at IS NULL.
/// Ne retourne que le champ `rent_amount_cents` (loyer HC) pour le compute engine.
///
/// Évite un import circulaire entre properties et leases.
final activeLeaseRentProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, propertyId) async {
    _log.info('activeLeaseRentProvider($propertyId)');
    final rows = await Db.from('leases')
        .select('rent_amount_cents')
        .eq('property_id', propertyId)
        .eq('status', 'active')
        .filter('deleted_at', 'is', null)
        .limit(1);
    if (rows.isEmpty) return null;
    final raw = rows.first['rent_amount_cents'];
    return raw as int?;
  },
);

/// Retourne l'identifiant du bail actif pour un bien donné, ou null si vacant.
///
/// Utilisé par l'UI pour le CTA "Voir le bail" ou "Créer un bail".
final activeLeaseIdProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, propertyId) async {
      _log.info('activeLeaseIdProvider($propertyId)');
      final rows = await Db.from('leases')
          .select('id')
          .eq('property_id', propertyId)
          .eq('status', 'active')
          .filter('deleted_at', 'is', null)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['id'] as String?;
    });

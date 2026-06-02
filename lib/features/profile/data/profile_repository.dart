import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db.dart';
import '../domain/landlord_profile.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('ProfileRepository');

/// Contrat public du repository profil bailleur.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class ProfileRepository {
  /// Retourne le profil du bailleur connecté (auth.uid()).
  ///
  /// Lance [ProfileNotFoundException] si la RLS renvoie 0 ligne.
  /// RLS `landlord_selects_self` filtre automatiquement.
  Future<LandlordProfile> getCurrent();

  /// Met à jour les champs éditables du profil bailleur.
  ///
  /// Seuls [fullName], [phone] et [address] sont inclus dans le payload UPDATE.
  /// Ne jamais envoyer `id`, `email`, `created_at`, `updated_at` — immutables.
  /// Le trigger `tr_02_set_updated_at_landlords` met à jour `updated_at`
  /// automatiquement côté Postgres.
  Future<LandlordProfile> update({
    required String? fullName,
    required String? phone,
    required String? address,
  });
}

/// Implémentation Supabase du [ProfileRepository].
class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository();

  @override
  Future<LandlordProfile> getCurrent() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw const ProfileNotFoundException();
    }
    _log.info('getCurrent()');
    // On utilise Db.from pour respecter le schéma d'env (public vs dev).
    // RLS `landlord_selects_self` : `id = auth.uid() AND deleted_at IS NULL`.
    final rows = await Db.from('landlords')
        .select('id, email, full_name, phone, address, created_at, updated_at')
        .eq('id', userId)
        .limit(1);

    if (rows.isEmpty) {
      throw const ProfileNotFoundException();
    }
    return LandlordProfile.fromJson(rows.first);
  }

  @override
  Future<LandlordProfile> update({
    required String? fullName,
    required String? phone,
    required String? address,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw const ProfileNotFoundException();
    }
    _log.info('update()');
    // Seuls les champs éditables — JAMAIS id, email, created_at, updated_at.
    // phone null est envoyé explicitement pour effacer la valeur.
    final payload = <String, dynamic>{
      'full_name': fullName?.trim().isEmpty == true ? null : fullName?.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
    };
    final rows = await Db.from('landlords')
        .update(payload)
        .eq('id', userId)
        .select('id, email, full_name, phone, address, created_at, updated_at');

    if (rows.isEmpty) {
      throw const ProfileNotFoundException();
    }
    return LandlordProfile.fromJson(rows.first);
  }
}

/// Exception levée quand le profil bailleur est introuvable ou session absente.
class ProfileNotFoundException implements Exception {
  const ProfileNotFoundException();

  @override
  String toString() => 'ProfileNotFoundException: profil bailleur introuvable';
}

/// Provider exposant le repository profil.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const SupabaseProfileRepository();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/profile_repository.dart';
import '../domain/landlord_profile.dart';

final _log = Logger('LandlordProfileNotifier');

/// Notifier qui charge et expose le profil du bailleur connecté.
///
/// Utilise [AsyncNotifier] (pas autoDispose) car le profil est partagé
/// entre plusieurs pages (ProfilePage, ProfilePage, dialog FEAT-007).
class LandlordProfileNotifier extends AsyncNotifier<LandlordProfile> {
  @override
  Future<LandlordProfile> build() async {
    _log.info('build — chargement du profil bailleur');
    return ref.read(profileRepositoryProvider).getCurrent();
  }

  /// Recharge le profil depuis Supabase.
  ///
  /// À appeler après une mise à jour réussie depuis [ProfileFormController].
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getCurrent(),
    );
  }
}

/// Provider du profil bailleur.
///
/// Consommé par [ProfilePage] pour le pré-remplissage du formulaire, et par
/// la future logique de garde FEAT-007 (full_name/address non NULL requis pour
/// générer une quittance).
final landlordProfileProvider =
    AsyncNotifierProvider<LandlordProfileNotifier, LandlordProfile>(
      LandlordProfileNotifier.new,
    );

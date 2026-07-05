import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/profile_repository.dart';
import '../domain/profile_form_state.dart';
import 'landlord_profile_provider.dart';

final _log = Logger('ProfileFormController');

/// Contrôle le formulaire de mise à jour du profil bailleur.
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// de la page — cohérent avec le pattern des autres formulaires du projet.
class ProfileFormController extends StateNotifier<ProfileFormState> {
  ProfileFormController(this._ref) : super(const ProfileFormState.idle());

  final Ref _ref;

  /// Soumet les champs du profil à Supabase.
  ///
  /// Sur succès : invalide [landlordProfileProvider] pour que tous les
  /// consumers obtiennent les données fraîches.
  Future<void> submit({
    required String? fullName,
    required String? phone,
    required String? address,
  }) async {
    state = const ProfileFormState.submitting();

    try {
      await _ref
          .read(profileRepositoryProvider)
          .update(fullName: fullName, phone: phone, address: address);
      _log.info('profil mis à jour');

      // Invalider le cache du profil pour que les consumers (ProfilePage,
      // futurs widgets FEAT-007) obtiennent les données fraîches.
      _ref.invalidate(landlordProfileProvider);

      state = const ProfileFormState.success();
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException lors de update profil', e, st);
      state = const ProfileFormState.error(
        message: 'Erreur lors de la sauvegarde du profil. Réessayez.',
      );
    } on ProfileNotFoundException catch (e, st) {
      _log.warning('ProfileNotFoundException lors de update', e, st);
      state = const ProfileFormState.error(
        message: 'Profil introuvable. Reconnectez-vous et réessayez.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de update profil', e, st);
      state = const ProfileFormState.error(
        message: 'Impossible de mettre à jour le profil. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const ProfileFormState.idle();
}

/// Provider autoDispose du contrôleur de formulaire profil.
final profileFormControllerProvider =
    StateNotifierProvider.autoDispose<ProfileFormController, ProfileFormState>(
      (ref) => ProfileFormController(ref),
    );

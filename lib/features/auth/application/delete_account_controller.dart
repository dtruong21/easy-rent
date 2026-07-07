import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/delete_account_reauth_method.dart';
import '../domain/delete_account_state.dart';
import 'auth_session_provider.dart';

final _log = Logger('DeleteAccountController');

/// Méthode de réauthentification à présenter dans le flux de suppression
/// de compte, dérivée des providers du user courant (FEAT-045).
///
/// Priorité : mot de passe (le plus simple in-app) > Google > Apple. Un
/// compte multi-providers (ex. email + Google lié) passe donc par son mot
/// de passe. Session anonyme → [DeleteAccountReauthMethod.none] (rien à
/// re-présenter, cf. enum).
///
/// Même défense loading/erreur que [hasPasswordProvider] : fallback sur
/// `currentUser` en cache.
final deleteAccountReauthMethodProvider = Provider<DeleteAccountReauthMethod>((
  ref,
) {
  final async = ref.watch(authStateChangesProvider);
  final user =
      async.asData?.value ?? ref.read(authRepositoryProvider).currentUser;
  if (user == null || user.isAnonymous) {
    return DeleteAccountReauthMethod.none;
  }
  final providerIds = user.providerData.map((p) => p.providerId).toSet();
  if (providerIds.contains('password')) {
    return DeleteAccountReauthMethod.password;
  }
  if (providerIds.contains('google.com')) {
    return DeleteAccountReauthMethod.google;
  }
  if (providerIds.contains('apple.com')) {
    return DeleteAccountReauthMethod.apple;
  }
  // Compte complet sans provider connu — ne devrait pas exister (Baillan
  // n'offre que email/Google/Apple). La callable refusera de toute façon
  // un token sans authentification fraîche.
  return DeleteAccountReauthMethod.none;
});

/// Orchestre la suppression de compte (FEAT-045, RGPD art. 17) :
/// réauthentification fraîche → révocation du token Apple le cas échéant
/// (App Store 5.1.1(v)) → callable `deleteAccount` (purge backend) →
/// session locale fermée par le repository.
class DeleteAccountController extends StateNotifier<DeleteAccountState> {
  DeleteAccountController(this._repository)
    : super(const DeleteAccountState.idle());

  final AuthRepository _repository;

  /// Compte email : réauthentifie avec le mot de passe actuel puis purge.
  Future<void> submitWithPassword(String currentPassword) => _run(() async {
    await _repository.reauthenticateWithPassword(currentPassword);
  });

  /// Compte Google : réauthentifie via le flux OAuth puis purge.
  Future<void> submitWithGoogle() => _run(() async {
    await _repository.reauthenticateWithOAuthProvider('google.com');
  });

  /// Compte Apple : réauthentifie via le flux OAuth, révoque le token
  /// Apple si un authorizationCode est fourni (iOS/macOS), puis purge.
  Future<void> submitWithApple() => _run(() async {
    final authorizationCode = await _repository.reauthenticateWithOAuthProvider(
      'apple.com',
    );
    if (authorizationCode != null) {
      // Best-effort par contrat du repository : n'échoue jamais.
      await _repository.revokeAppleToken(authorizationCode);
    } else {
      _log.info(
        'no Apple authorizationCode on this platform — revocation skipped',
      );
    }
  });

  /// Session anonyme : aucun credential à re-présenter, purge directe
  /// (la callable exempte les tokens anonymes de la garde de fraîcheur).
  Future<void> submitWithoutReauth() => _run(() async {});

  Future<void> _run(Future<void> Function() reauthenticate) async {
    state = const DeleteAccountState.working();
    try {
      await reauthenticate();
      await _repository.deleteAccount();
      state = const DeleteAccountState.success();
      _log.info('account deletion completed');
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('deleteAccount callable failed (code=${e.code})', e, st);
      state = DeleteAccountState.error(message: _mapFunctionsError(e));
    } on FirebaseAuthException catch (e, st) {
      _log.warning('deleteAccount reauth failed (code=${e.code})', e, st);
      state = DeleteAccountState.error(message: _mapAuthError(e));
    } catch (e, st) {
      _log.severe('unexpected deleteAccount failure', e, st);
      state = const DeleteAccountState.error(
        message: 'La suppression a échoué. Veuillez réessayer.',
      );
    }
  }

  /// Remet le flux à l'état initial (après affichage d'une erreur).
  void reset() => state = const DeleteAccountState.idle();

  /// Contexte « mot de passe actuel » : même surcharge de libellés que
  /// [ChangePasswordController] (le mapper mutualisé mentionne « Email »,
  /// hors sujet pour un utilisateur déjà connecté).
  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mot de passe actuel incorrect.';
      case 'user-mismatch':
        return 'Le compte confirmé ne correspond pas au compte connecté. '
            'Réessayez avec le même compte.';
      default:
        return AuthErrorMapper.fromException(e);
    }
  }

  String _mapFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      // Garde serveur `recent-login-required` (auth_time > 5 min) : la
      // réauthentification vient d'avoir lieu, ce cas signale une horloge
      // très décalée ou un flux contourné — on redemande une connexion.
      case 'failed-precondition':
        return 'Votre session est trop ancienne. Reconnectez-vous puis '
            'réessayez.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Connexion impossible. Vérifiez votre accès internet et '
            'réessayez.';
      default:
        return 'La suppression a échoué. Veuillez réessayer.';
    }
  }
}

final deleteAccountControllerProvider =
    StateNotifierProvider.autoDispose<
      DeleteAccountController,
      DeleteAccountState
    >((ref) => DeleteAccountController(ref.read(authRepositoryProvider)));

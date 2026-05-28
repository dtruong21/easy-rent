import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/email_validator.dart';
import '../data/auth_repository.dart';
import '../domain/login_form_state.dart';

final _log = Logger('AuthController');

/// Contrôle le formulaire de connexion.
///
/// Expose [LoginFormState] et les actions :
/// - [sendMagicLink] : valide l'email + la case RGPD, puis appelle le repo.
/// - [signOut] : révoque la session et réinitialise le state.
/// - [reset] : repasse à [LoginFormState.idle] (ex. : bouton "Renvoyer").
class AuthController extends StateNotifier<LoginFormState> {
  AuthController(this._repository) : super(const LoginFormState.idle());

  final AuthRepository _repository;

  /// Envoie un magic link après validation côté client.
  ///
  /// Conditions de soumission (toutes obligatoires) :
  /// - [email] valide (format RFC-5322 simplifié)
  /// - [rgpdConsent] coché par l'utilisateur
  Future<void> sendMagicLink({
    required String email,
    required bool rgpdConsent,
  }) async {
    // Validation email
    if (!EmailValidator.isValid(email)) {
      state = const LoginFormState.error(message: 'Adresse email invalide');
      return;
    }

    // Validation consentement RGPD
    if (!rgpdConsent) {
      state = const LoginFormState.error(
        message: 'Vous devez accepter la politique de confidentialité',
      );
      return;
    }

    state = const LoginFormState.submitting();

    try {
      await _repository.sendMagicLink(email.trim());
      state = LoginFormState.linkSent(email: email.trim());
      // L'email n'est PAS logué (donnée personnelle RGPD).
      _log.info('Magic link envoyé avec succès');
    } on AuthException catch (e, st) {
      _log.warning('AuthException lors de sendMagicLink', e, st);
      state = LoginFormState.error(message: _mapAuthError(e.message));
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de sendMagicLink', e, st);
      state = const LoginFormState.error(
        message: "Une erreur est survenue. Veuillez réessayer.",
      );
    }
  }

  /// Révoque la session Supabase et réinitialise le formulaire.
  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (e, st) {
      _log.severe('Erreur lors de signOut', e, st);
    } finally {
      state = const LoginFormState.idle();
    }
  }

  /// Repasse à l'état initial (utilisé par le bouton "Renvoyer un lien").
  void reset() => state = const LoginFormState.idle();

  String _mapAuthError(String raw) {
    if (raw.toLowerCase().contains('rate limit')) {
      return 'Trop de demandes. Attendez quelques minutes avant de réessayer.';
    }
    if (raw.toLowerCase().contains('invalid email')) {
      return 'Adresse email invalide';
    }
    return "Impossible d'envoyer le lien. Vérifiez votre email et réessayez.";
  }
}

/// Provider du contrôleur de formulaire.
final authControllerProvider =
    StateNotifierProvider<AuthController, LoginFormState>((ref) {
      return AuthController(ref.read(authRepositoryProvider));
    });

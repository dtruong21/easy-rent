import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/email_validator.dart';
import '../../../core/utils/password_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/auth_cta_label.dart';
import '../domain/auth_error.dart';
import '../domain/signup_page_state.dart';

final _log = Logger('SignupController');

class SignupController extends StateNotifier<SignupPageState> {
  SignupController(this._repository) : super(const SignupPageState.idle());

  final AuthRepository _repository;

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
    required bool rgpdConsent,
  }) async {
    if (fullName.trim().isEmpty) {
      state = SignupPageState.error(message: AuthError.fullNameRequired.name);
      return;
    }
    if (!EmailValidator.isValid(email)) {
      state = SignupPageState.error(message: AuthError.invalidEmailFormat.name);
      return;
    }
    final passwordError = PasswordValidator.validate(password);
    if (passwordError != null) {
      state = SignupPageState.error(message: passwordError.name);
      return;
    }
    if (password != confirmPassword) {
      state = SignupPageState.error(message: AuthError.passwordsMismatch.name);
      return;
    }
    if (!rgpdConsent) {
      state = SignupPageState.error(message: AuthError.consentRequired.name);
      return;
    }

    state = const SignupPageState.submitting();
    try {
      // BAILLAN-M1 : un visiteur en session anonyme (essai simulateur sans
      // compte) qui remplit le formulaire de création de compte doit être
      // LIÉ (préserve UID + scénarios sauvegardés) plutôt que de créer un
      // second compte. Transparent pour l'UI — `SignupForm` ne change pas.
      if (_repository.currentUser?.isAnonymous ?? false) {
        await _repository.linkAnonymousWithEmailPassword(
          email: email.trim(),
          password: password,
          fullName: fullName.trim(),
          rgpdConsent: rgpdConsent,
        );
      } else {
        await _repository.signUpWithPassword(
          email: email.trim(),
          password: password,
          fullName: fullName.trim(),
        );
      }
      // Le repository a envoyé l'email de vérification puis signé out. On
      // reste sur /signup avec la vue SignupConfirmationSentView jusqu'au
      // clic du lien reçu par email. L'utilisateur devra ensuite se
      // connecter manuellement via /login.
      state = const SignupPageState.awaitingConfirmation();
      _log.info('Signup réussi — email de vérification envoyé');
    } on FirebaseAuthException catch (e, st) {
      _log.warning('FirebaseAuthException signup (code=${e.code})', e, st);
      state = SignupPageState.error(
        message: AuthErrorMapper.fromException(e).name,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue signup', e, st);
      state = SignupPageState.error(message: AuthError.unknown.name);
    }
  }

  /// Crée un compte (ou connecte un compte existant) via Google.
  ///
  /// [rgpdConsent] est capturé au moment du clic (snapshot du state de la
  /// checkbox RGPD côté widget) — défense en profondeur : même si le widget
  /// autorisait l'appel par erreur, ce guard rejette toute tentative sans
  /// consentement explicite avant d'ouvrir le popup Google.
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      state = SignupPageState.error(message: AuthError.consentRequired.name);
      return;
    }

    state = const SignupPageState.submitting();
    try {
      // BAILLAN-M1 : anon → link (préserve UID + scénarios), sinon signup
      // classique. Transparent pour l'UI.
      if (_repository.currentUser?.isAnonymous ?? false) {
        await _repository.linkAnonymousWithGoogle(rgpdConsent: rgpdConsent);
      } else {
        await _repository.signUpWithGoogle(rgpdConsent: rgpdConsent);
      }
      state = const SignupPageState.idle();
      _log.info('Signup Google réussi — session active');
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException signUpWithGoogle (code=${e.code})',
        e,
        st,
      );
      final isAccountConflict =
          e.code == 'account-exists-with-different-credential';
      state = SignupPageState.error(
        message: AuthErrorMapper.fromException(e).name,
        ctaRoute: isAccountConflict ? '/login' : null,
        ctaLabel: isAccountConflict ? AuthCtaLabel.signIn.name : null,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue signUpWithGoogle', e, st);
      state = SignupPageState.error(message: AuthError.unknown.name);
    }
  }

  /// Crée un compte (ou connecte un compte existant) via Apple.
  ///
  /// [rgpdConsent] est capturé au moment du clic (snapshot du state de la
  /// checkbox RGPD côté widget) — défense en profondeur : même si le widget
  /// autorisait l'appel par erreur, ce guard rejette toute tentative sans
  /// consentement explicite avant d'ouvrir le popup Apple.
  Future<void> signUpWithApple({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      state = SignupPageState.error(message: AuthError.consentRequired.name);
      return;
    }

    state = const SignupPageState.submitting();
    try {
      // BAILLAN-M1 : anon → link (préserve UID + scénarios), sinon signup
      // classique. Transparent pour l'UI.
      if (_repository.currentUser?.isAnonymous ?? false) {
        await _repository.linkAnonymousWithApple(rgpdConsent: rgpdConsent);
      } else {
        await _repository.signUpWithApple(rgpdConsent: rgpdConsent);
      }
      state = const SignupPageState.idle();
      _log.info('Signup Apple réussi — session active');
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException signUpWithApple (code=${e.code})',
        e,
        st,
      );
      final isAccountConflict =
          e.code == 'account-exists-with-different-credential';
      state = SignupPageState.error(
        message: AuthErrorMapper.fromException(e).name,
        ctaRoute: isAccountConflict ? '/login' : null,
        ctaLabel: isAccountConflict ? AuthCtaLabel.signIn.name : null,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue signUpWithApple', e, st);
      state = SignupPageState.error(message: AuthError.unknown.name);
    }
  }
}

final signupControllerProvider =
    StateNotifierProvider<SignupController, SignupPageState>((ref) {
      return SignupController(ref.read(authRepositoryProvider));
    });

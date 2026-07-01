import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/email_validator.dart';
import '../data/apple_auth_exception.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../data/google_auth_exception.dart';
import '../domain/login_page_state.dart';

final _log = Logger('LoginController');

class LoginController extends StateNotifier<LoginPageState> {
  LoginController(this._repository) : super(const LoginPageState.idle());

  final AuthRepository _repository;

  Future<void> signIn({required String email, required String password}) async {
    if (!EmailValidator.isValid(email)) {
      state = const LoginPageState.error(message: 'Adresse email invalide');
      return;
    }
    if (password.isEmpty) {
      state = const LoginPageState.error(message: 'Mot de passe requis');
      return;
    }

    state = const LoginPageState.submitting();
    try {
      await _repository.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      // Guard email verification (FEAT-021). `reload()` force la synchro
      // du champ `emailVerified` — un email vérifié post-signup ne se
      // reflète pas côté client sans reload.
      final user = _repository.currentUser;
      await user?.reload();
      final refreshed = _repository.currentUser;

      if (refreshed != null && !refreshed.emailVerified) {
        // Renvoie automatiquement un email de vérification puis signe out.
        // Le simple fait de tenter de se connecter avant vérification
        // relance le mail — pas besoin de bouton "Renvoyer" explicite.
        try {
          await _repository.sendCurrentUserEmailVerification();
        } catch (e, st) {
          _log.warning('resend verification email failed', e, st);
        }
        await _repository.signOut();
        state = const LoginPageState.error(
          message:
              'Votre email n\'est pas encore vérifié. Nous venons de vous '
              'renvoyer le lien de confirmation — vérifiez votre boîte mail.',
        );
        return;
      }

      // Succès : authStateChanges déclenche GoRouter via GoRouterRefreshStream
      // → redirect vers /. Pas besoin de changer le state ici.
      state = const LoginPageState.idle();
    } on FirebaseAuthException catch (e, st) {
      _log.warning('FirebaseAuthException signIn (code=${e.code})', e, st);
      state = LoginPageState.error(message: AuthErrorMapper.fromException(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue signIn', e, st);
      state = const LoginPageState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Connecte avec un compte Google existant.
  ///
  /// Ne crée jamais de nouveau compte : si le repo détecte un Google inconnu
  /// de Baillan, l'erreur [GoogleAuthErrorCode.newUserOnLogin] est mappée en
  /// état error avec un CTA contextuel vers `/signup`.
  Future<void> signInWithGoogle() async {
    state = const LoginPageState.submitting();
    try {
      await _repository.signInWithGoogle();
      state = const LoginPageState.idle();
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException signInWithGoogle (code=${e.code})',
        e,
        st,
      );
      final isNewUserOnLogin = e.code == GoogleAuthErrorCode.newUserOnLogin;
      state = LoginPageState.error(
        message: AuthErrorMapper.fromException(e),
        ctaRoute: isNewUserOnLogin ? '/signup' : null,
        ctaLabel: isNewUserOnLogin ? 'Créer un compte' : null,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue signInWithGoogle', e, st);
      state = const LoginPageState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Connecte avec un compte Apple existant.
  ///
  /// Ne crée jamais de nouveau compte : si le repo détecte un Apple inconnu
  /// de Baillan, l'erreur [AppleAuthErrorCode.newUserOnLogin] est mappée en
  /// état error avec un CTA contextuel vers `/signup`.
  Future<void> signInWithApple() async {
    state = const LoginPageState.submitting();
    try {
      await _repository.signInWithApple();
      state = const LoginPageState.idle();
    } on FirebaseAuthException catch (e, st) {
      _log.warning(
        'FirebaseAuthException signInWithApple (code=${e.code})',
        e,
        st,
      );
      final isNewUserOnLogin = e.code == AppleAuthErrorCode.newUserOnLogin;
      state = LoginPageState.error(
        message: AuthErrorMapper.fromException(e),
        ctaRoute: isNewUserOnLogin ? '/signup' : null,
        ctaLabel: isNewUserOnLogin ? 'Créer un compte' : null,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue signInWithApple', e, st);
      state = const LoginPageState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (e, st) {
      _log.severe('Erreur lors de signOut', e, st);
    } finally {
      state = const LoginPageState.idle();
    }
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginPageState>((ref) {
      return LoginController(ref.read(authRepositoryProvider));
    });

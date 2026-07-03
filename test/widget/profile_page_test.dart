/// Tests widget de [ProfilePage].
///
/// Couvre :
/// - Pré-remplissage des champs si profil existant
/// - Champs requis vides → messages inline après soumission
/// - Submit valide → controller appelé + SnackBar succès
/// - État erreur → message inline affiché
/// - État submitting → bouton désactivé avec indicateur
/// - Email affiché en lecture seule
/// - Section Sécurité (FEAT-025) : gating par provider (password/Google/
///   Apple/anonyme), succès, erreurs de changement de mot de passe
/// - Section Support (FEAT-025) : validation, succès, échec
library;

import 'dart:async';

import 'package:easyrent/core/theme/theme_mode_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/profile/application/profile_form_controller.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/profile/domain/profile_form_state.dart';
import 'package:easyrent/features/profile/presentation/profile_page.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake repositories
// ---------------------------------------------------------------------------

class _FakeProfileRepository implements ProfileRepository {
  LandlordProfile? _profile;
  bool throwOnGet = false;
  bool throwOnUpdate = false;

  String? lastFullName;
  String? lastPhone;
  String? lastAddress;

  void seed(LandlordProfile profile) => _profile = profile;

  @override
  Future<LandlordProfile> getCurrent() async {
    if (throwOnGet) throw const ProfileNotFoundException();
    final p = _profile;
    if (p == null) throw const ProfileNotFoundException();
    return p;
  }

  @override
  Future<LandlordProfile> update({
    required String? fullName,
    required String? phone,
    required String? address,
  }) async {
    if (throwOnUpdate) throw Exception('network error');
    lastFullName = fullName;
    lastPhone = phone;
    lastAddress = address;
    final p = _profile!;
    final updated = p.copyWith(
      fullName: fullName,
      phone: phone,
      address: address,
    );
    _profile = updated;
    return updated;
  }
}

/// Fake [AuthRepository] dont on contrôle le [User] exposé (pour
/// [hasPasswordProvider]) et les 2 appels du flow de changement de mot de
/// passe in-app (FEAT-025).
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final User? _user;

  bool reauthenticateCalled = false;
  bool updatePasswordCalled = false;
  String? lastCurrentPassword;
  String? lastNewPassword;

  /// Si non-null, jeté par [reauthenticateWithPassword].
  FirebaseAuthException? reauthenticateError;

  /// Si non-null, [reauthenticateWithPassword] attend que ce [Completer]
  /// soit complété avant de retourner — permet d'observer l'état
  /// `submitting` dans les tests (sans ce hook, le Future se résoudrait
  /// avant le prochain `pump()`).
  Completer<void>? reauthenticateGate;

  @override
  Stream<User?> get authStateChanges => Stream.value(_user);

  @override
  User? get currentUser => _user;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {}

  @override
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> linkAnonymousWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required bool rgpdConsent,
  }) async {}

  @override
  Future<void> linkAnonymousWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> linkAnonymousWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'test@example.com';

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {
    reauthenticateCalled = true;
    lastCurrentPassword = currentPassword;
    final gate = reauthenticateGate;
    if (gate != null) await gate.future;
    final err = reauthenticateError;
    if (err != null) throw err;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalled = true;
    lastNewPassword = newPassword;
  }

  @override
  Future<void> signOut() async {}
}

/// Fake [SupportRepository] — enregistre le dernier appel pour assertion.
class _FakeSupportRepository implements SupportRepository {
  bool submitCalled = false;
  String? lastSubject;
  String? lastMessage;
  String? lastAppVersion;
  String? lastAppEnv;
  Exception? submitError;

  /// Si non-null, [submit] attend que ce [Completer] soit complété avant de
  /// retourner — permet d'observer l'état `submitting` dans les tests.
  Completer<void>? submitGate;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {
    submitCalled = true;
    lastSubject = subject;
    lastMessage = message;
    lastAppVersion = appVersion;
    lastAppEnv = appEnv;
    final gate = submitGate;
    if (gate != null) await gate.future;
    final err = submitError;
    if (err != null) throw err;
  }
}

// ---------------------------------------------------------------------------
// Faker le User / providerData (firebase_auth_mocks)
// ---------------------------------------------------------------------------

UserInfo _providerInfo(String providerId) => UserInfo.fromJson({
  'uid': 'uid-1',
  'email': 'test@example.com',
  'displayName': null,
  'photoUrl': null,
  'phoneNumber': null,
  'isAnonymous': false,
  'isEmailVerified': true,
  'providerId': providerId,
  'tenantId': null,
  'refreshToken': null,
  'creationTimestamp': null,
  'lastSignInTimestamp': null,
});

MockUser _passwordUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'test@example.com',
  providerData: [_providerInfo('password')],
);

MockUser _googleUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'g@example.com',
  providerData: [_providerInfo('google.com')],
);

MockUser _appleUser() => MockUser(
  isAnonymous: false,
  uid: 'uid-1',
  email: 'a@example.com',
  providerData: [_providerInfo('apple.com')],
);

MockUser _anonUser() => MockUser(isAnonymous: true, uid: 'uid-a');

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

LandlordProfile _makeProfile({
  String? fullName,
  String? phone,
  String? address,
}) => LandlordProfile(
  id: 'uid-1',
  email: 'test@example.com',
  fullName: fullName,
  phone: phone,
  address: address,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  rgpdConsentAt: DateTime(2024),
  rgpdConsentVersion: 'legacy-1',
);

Widget _buildPage({
  required _FakeProfileRepository repo,
  ProfileFormState? initialFormState,
  _FakeAuthRepository? authRepo,
  _FakeSupportRepository? supportRepo,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfilePage()),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const Scaffold(body: Text('page cgu')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const Scaffold(body: Text('page privacy')),
      ),
    ],
  );

  // Fake par défaut = compte email (providerData contient 'password') pour
  // ne pas casser les tests existants qui ne s'occupent pas de la section
  // Sécurité (elle sera juste présente et inerte).
  final resolvedAuthRepo = authRepo ?? _FakeAuthRepository(_passwordUser());

  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(resolvedAuthRepo),
      supportRepositoryProvider.overrideWithValue(
        supportRepo ?? _FakeSupportRepository(),
      ),
      if (initialFormState != null)
        profileFormControllerProvider.overrideWith(
          (ref) => ProfileFormController(ref)..state = initialFormState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfilePage — smoke tests', () {
    // -----------------------------------------------------------------------
    // Titre et structure
    // -----------------------------------------------------------------------
    testWidgets('titre "Mon profil" affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Mon profil'), findsOneWidget);
    });

    testWidgets('les 3 champs éditables + email readonly sont présents', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_email_readonly')), findsOneWidget);
      expect(find.byKey(const Key('field_full_name')), findsOneWidget);
      expect(find.byKey(const Key('field_phone')), findsOneWidget);
      expect(find.byKey(const Key('field_address')), findsOneWidget);
    });

    testWidgets('bouton "Enregistrer" présent', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_save_profile')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Pré-remplissage avec profil existant
    // -----------------------------------------------------------------------
    testWidgets('pré-remplissage si profil complet', (tester) async {
      final repo = _FakeProfileRepository()
        ..seed(
          _makeProfile(
            fullName: 'Marie Martin',
            phone: '06 12 34 56 78',
            address: '12 rue de la Paix\n75001 Paris',
          ),
        );
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Marie Martin'), findsOneWidget);
      expect(find.text('06 12 34 56 78'), findsOneWidget);
      // findsWidgets : le hint text du champ adresse contient aussi "12 rue de la Paix".
      expect(find.textContaining('12 rue de la Paix'), findsWidgets);
    });

    testWidgets('email affiché depuis le profil chargé', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('champs vides si profil sans fullName ni address', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      final fullNameField = tester.widget<TextFormField>(
        find.byKey(const Key('field_full_name')),
      );
      expect((fullNameField.controller?.text ?? ''), isEmpty);
    });

    // -----------------------------------------------------------------------
    // Validation — champs requis vides
    // -----------------------------------------------------------------------
    testWidgets('validation — erreur fullName si vide à la soumission', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save_profile')));
      await tester.pumpAndSettle();

      expect(find.textContaining('obligatoire'), findsWidgets);
    });

    testWidgets('validation — erreur address si vide à la soumission', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      // Remplir fullName seulement
      await tester.enterText(
        find.byKey(const Key('field_full_name')),
        'Jean Dupont',
      );
      await tester.tap(find.byKey(const Key('btn_save_profile')));
      await tester.pumpAndSettle();

      expect(find.textContaining('obligatoire'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // État submitting
    // -----------------------------------------------------------------------
    testWidgets('état submitting — bouton désactivé avec indicateur', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(
        _buildPage(
          repo: repo,
          initialFormState: const ProfileFormState.submitting(),
        ),
      );
      // pump() et non pumpAndSettle() : CircularProgressIndicator anime
      // indéfiniment et pumpAndSettle() ne se terminerait jamais.
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_save_profile')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État erreur
    // -----------------------------------------------------------------------
    testWidgets('état erreur — message inline affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(
        _buildPage(
          repo: repo,
          initialFormState: const ProfileFormState.error(
            message:
                'Impossible de mettre à jour le profil. Veuillez réessayer.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Impossible de mettre à jour'),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Chargement initial — erreur du profil
    // -----------------------------------------------------------------------
    testWidgets('erreur de chargement — bouton Réessayer affiché', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..throwOnGet = true;
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('ProfilePage — réglages (apparence, légal, à propos, session)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Baillan',
        packageName: 'app.baillan',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '',
        installerStore: null,
      );
    });

    testWidgets('sections et contrôles présents', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Apparence'), findsOneWidget);
      expect(find.byKey(const Key('segments_theme_mode')), findsOneWidget);
      expect(find.text('Légal'), findsOneWidget);
      expect(find.byKey(const Key('tile_terms')), findsOneWidget);
      expect(find.byKey(const Key('tile_privacy')), findsOneWidget);
      expect(find.text('À propos'), findsOneWidget);
      expect(find.byKey(const Key('btn_logout_profile')), findsOneWidget);
    });

    testWidgets('À propos — version, build et environnement affichés', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      // APP_ENV absent en test → défaut 'dev' → libellé dev/staging.
      expect(
        find.text('Baillan. v1.0.0 (build 42) · dev/staging'),
        findsOneWidget,
      );
    });

    testWidgets('choisir « Sombre » applique et persiste le thème', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('segments_theme_mode')));
      await tester.tap(find.text('Sombre'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfilePage)),
      );
      expect(container.read(themeModeProvider), ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    testWidgets('tile CGU → navigue vers /terms', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('tile_terms')));
      await tester.tap(find.byKey(const Key('tile_terms')));
      await tester.pumpAndSettle();

      expect(find.text('page cgu'), findsOneWidget);
    });

    testWidgets('tile Confidentialité → navigue vers /privacy', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('tile_privacy')));
      await tester.tap(find.byKey(const Key('tile_privacy')));
      await tester.pumpAndSettle();

      expect(find.text('page privacy'), findsOneWidget);
    });
  });

  group('ProfilePage — section Sécurité (FEAT-025)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Baillan',
        packageName: 'app.baillan',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '',
        installerStore: null,
      );
    });

    testWidgets('compte email → section Sécurité visible', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.text('Sécurité'), findsOneWidget);
      expect(find.byKey(const Key('field_current_password')), findsOneWidget);
      expect(find.byKey(const Key('field_new_password')), findsOneWidget);
      expect(find.byKey(const Key('field_confirm_password')), findsOneWidget);
      expect(find.byKey(const Key('btn_change_password')), findsOneWidget);
    });

    testWidgets('compte Google → rien affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_googleUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.text('Sécurité'), findsNothing);
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });

    testWidgets('compte Apple → rien affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_appleUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.text('Sécurité'), findsNothing);
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });

    testWidgets('session anonyme → rien affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_anonUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.text('Sécurité'), findsNothing);
      expect(find.byKey(const Key('field_current_password')), findsNothing);
    });

    testWidgets(
      'succès — repo appelé (reauth puis update), snackbar, champs vidés',
      (tester) async {
        final repo = _FakeProfileRepository()..seed(_makeProfile());
        final authRepo = _FakeAuthRepository(_passwordUser());
        await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_current_password')),
          'OldPassword1',
        );
        await tester.enterText(
          find.byKey(const Key('field_new_password')),
          'NewPassword2',
        );
        await tester.enterText(
          find.byKey(const Key('field_confirm_password')),
          'NewPassword2',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('btn_change_password')),
        );
        await tester.tap(find.byKey(const Key('btn_change_password')));
        await tester.pumpAndSettle();

        expect(authRepo.reauthenticateCalled, isTrue);
        expect(authRepo.lastCurrentPassword, 'OldPassword1');
        expect(authRepo.updatePasswordCalled, isTrue);
        expect(authRepo.lastNewPassword, 'NewPassword2');

        expect(find.text('Mot de passe mis à jour'), findsOneWidget);

        final currentField = tester.widget<TextField>(
          find
              .descendant(
                of: find.byKey(const Key('field_current_password')),
                matching: find.byType(TextField),
              )
              .first,
        );
        expect(currentField.controller?.text ?? '', isEmpty);
      },
    );

    testWidgets(
      'mot de passe actuel erroné → message dédié, updatePassword jamais appelé',
      (tester) async {
        final repo = _FakeProfileRepository()..seed(_makeProfile());
        final authRepo = _FakeAuthRepository(_passwordUser())
          ..reauthenticateError = FirebaseAuthException(
            code: 'wrong-password',
            message: 'wrong password',
          );
        await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_current_password')),
          'WrongPassword1',
        );
        await tester.enterText(
          find.byKey(const Key('field_new_password')),
          'NewPassword2',
        );
        await tester.enterText(
          find.byKey(const Key('field_confirm_password')),
          'NewPassword2',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('btn_change_password')),
        );
        await tester.tap(find.byKey(const Key('btn_change_password')));
        await tester.pumpAndSettle();

        expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
        expect(authRepo.updatePasswordCalled, isFalse);
      },
    );

    testWidgets('invalid-credential → même message dédié que wrong-password', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser())
        ..reauthenticateError = FirebaseAuthException(
          code: 'invalid-credential',
          message: 'invalid credential',
        );
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'WrongPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'NewPassword2',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();

      expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
      expect(authRepo.updatePasswordCalled, isFalse);
    });

    testWidgets('nouveau mot de passe == actuel → refusé sans appel repo', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'SamePassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'SamePassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'SamePassword1',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();

      expect(
        find.text('Le nouveau mot de passe doit être différent de l\'actuel.'),
        findsOneWidget,
      );
      expect(authRepo.reauthenticateCalled, isFalse);
      expect(authRepo.updatePasswordCalled, isFalse);
    });

    testWidgets('confirmation différente → message dédié, aucun appel repo', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'OldPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'Different3',
      );
      await tester.pump();

      // Le bouton est désactivé côté UI (_canSubmit) tant que confirm !=
      // new — pas de tap possible ; on valide simplement l'état désactivé.
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_change_password')),
      );
      expect(btn.onPressed, isNull);
      expect(authRepo.reauthenticateCalled, isFalse);
    });

    testWidgets('bouton désactivé pendant submit', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final gate = Completer<void>();
      final authRepo = _FakeAuthRepository(_passwordUser())
        ..reauthenticateGate = gate;
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_current_password')),
        'OldPassword1',
      );
      await tester.enterText(
        find.byKey(const Key('field_new_password')),
        'NewPassword2',
      );
      await tester.enterText(
        find.byKey(const Key('field_confirm_password')),
        'NewPassword2',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();
      // `tap()` n'attend que le geste physique (down/up), pas la résolution
      // du Future retourné par `onPressed` — le submit reste bloqué sur
      // `gate.future` après ce await, ce qui permet d'observer l'état
      // `submitting` de façon déterministe.
      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_change_password')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Débloque le submit puis laisse le Future se résoudre pour éviter un
      // timer pending en fin de test.
      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('ProfilePage — section Support (FEAT-025)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Baillan',
        packageName: 'app.baillan',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '',
        installerStore: null,
      );
    });

    testWidgets('section présente avec champs et bouton', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Support'), findsOneWidget);
      expect(find.byKey(const Key('field_support_subject')), findsOneWidget);
      expect(find.byKey(const Key('field_support_message')), findsOneWidget);
      expect(find.byKey(const Key('btn_support_submit')), findsOneWidget);
    });

    testWidgets('bouton désactivé si sujet ou message vide', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn_support_submit')));
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_support_submit')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets(
      'succès — repo appelé avec landlordId/subject/message/appVersion/appEnv, snackbar, champs vidés',
      (tester) async {
        final repo = _FakeProfileRepository()..seed(_makeProfile());
        final authRepo = _FakeAuthRepository(_passwordUser());
        final supportRepo = _FakeSupportRepository();
        await tester.pumpWidget(
          _buildPage(repo: repo, authRepo: authRepo, supportRepo: supportRepo),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('field_support_subject')),
        );
        await tester.enterText(
          find.byKey(const Key('field_support_subject')),
          'Problème de quittance',
        );
        await tester.enterText(
          find.byKey(const Key('field_support_message')),
          'La quittance de mars ne se génère pas.',
        );
        await tester.pump();

        await tester.ensureVisible(find.byKey(const Key('btn_support_submit')));
        await tester.tap(find.byKey(const Key('btn_support_submit')));
        await tester.pumpAndSettle();

        expect(supportRepo.submitCalled, isTrue);
        expect(supportRepo.lastSubject, 'Problème de quittance');
        expect(
          supportRepo.lastMessage,
          'La quittance de mars ne se génère pas.',
        );
        expect(supportRepo.lastAppVersion, '1.0.0+42');
        expect(supportRepo.lastAppEnv, 'dev');

        expect(
          find.text('Message envoyé. Nous reviendrons vers vous par email.'),
          findsOneWidget,
        );

        final subjectField = tester.widget<TextFormField>(
          find.byKey(const Key('field_support_subject')),
        );
        expect(subjectField.controller?.text ?? '', isEmpty);
      },
    );

    testWidgets('échec réseau → message inline neutre retentable', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final supportRepo = _FakeSupportRepository()
        ..submitError = Exception('network down');
      await tester.pumpWidget(_buildPage(repo: repo, supportRepo: supportRepo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('field_support_subject')),
      );
      await tester.enterText(
        find.byKey(const Key('field_support_subject')),
        'Sujet',
      );
      await tester.enterText(
        find.byKey(const Key('field_support_message')),
        'Message',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_support_submit')));
      await tester.tap(find.byKey(const Key('btn_support_submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('Envoi impossible. Réessayez dans quelques instants.'),
        findsOneWidget,
      );
      // Retentable : le bouton redevient actif (les champs n'ont pas été
      // vidés, l'utilisateur peut relancer).
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_support_submit')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('bouton désactivé pendant submit', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final gate = Completer<void>();
      final supportRepo = _FakeSupportRepository()..submitGate = gate;
      await tester.pumpWidget(_buildPage(repo: repo, supportRepo: supportRepo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('field_support_subject')),
      );
      await tester.enterText(
        find.byKey(const Key('field_support_subject')),
        'Sujet',
      );
      await tester.enterText(
        find.byKey(const Key('field_support_message')),
        'Message',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn_support_submit')));
      await tester.pumpAndSettle();
      // Le submit reste bloqué sur `gate.future` après ce await (même
      // stratégie que section Sécurité).
      await tester.tap(find.byKey(const Key('btn_support_submit')));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_support_submit')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });
}

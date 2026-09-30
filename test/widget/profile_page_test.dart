/// Tests widget de [ProfilePage] — hub de réglages mobile-first.
///
/// Couvre :
/// - En-tête compact (nom + email), tolérance loading/erreur avec fallback
///   sur l'email auth
/// - Groupe Compte : tuile Informations personnelles toujours présente et
///   navigable, tuile Changer le mot de passe gatée par [hasPasswordProvider]
///   (présente pour un compte email, absente pour Google/Apple/anonyme) et
///   navigable
/// - Groupe Préférences : sélecteur de thème inline inchangé
/// - Groupe Aide : tuile Support navigable, tuiles légales (CGU,
///   confidentialité) navigables
/// - À propos et Se déconnecter inchangés
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_provider.dart';
import 'package:easyrent/core/theme/theme_mode_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/profile/presentation/change_password_page.dart';
import 'package:easyrent/features/profile/presentation/profile_details_page.dart';
import 'package:easyrent/features/profile/presentation/profile_page.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/presentation/support_page.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
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
/// [hasPasswordProvider]).
class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  _FakeAuthRepository(this._user);

  final User? _user;

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
  Future<void> reauthenticateWithPassword(String currentPassword) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}

/// Fake [SupportRepository] — inerte, utile pour monter `/profile/support`
/// après navigation.
class _FakeSupportRepository implements SupportRepository {
  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {}
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
  _FakeAuthRepository? authRepo,
  _FakeSupportRepository? supportRepo,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfilePage()),
      GoRoute(
        path: '/profile/details',
        builder: (context, state) => const ProfileDetailsPage(),
      ),
      GoRoute(
        path: '/profile/password',
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/profile/support',
        builder: (context, state) => const SupportPage(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const Scaffold(body: Text('page cgu')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const Scaffold(body: Text('page privacy')),
      ),
      GoRoute(
        path: '/legal',
        builder: (context, state) => const Scaffold(body: Text('page legal')),
      ),
      GoRoute(
        path: '/profile/delete-account',
        builder: (context, state) =>
            const Scaffold(body: Text('page suppression compte')),
      ),
      GoRoute(
        path: '/faq',
        builder: (context, state) => const Scaffold(body: Text('page faq')),
      ),
    ],
  );

  // Fake par défaut = compte email (providerData contient 'password') pour
  // ne pas casser les tests qui ne s'occupent pas du gating de la tuile
  // mot de passe (elle sera juste présente et inerte).
  final resolvedAuthRepo = authRepo ?? _FakeAuthRepository(_passwordUser());

  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(resolvedAuthRepo),
      supportRepositoryProvider.overrideWithValue(
        supportRepo ?? _FakeSupportRepository(),
      ),
    ],
    // Consumer (et non `locale: const Locale('fr')` fixe) : ce hub porte le
    // sélecteur de langue lui-même (FEAT-043) — il doit suivre
    // [localeProvider] en direct, comme `BaillanApp` (main.dart), sinon la
    // bascule ne se reflète jamais dans l'arbre de widgets sous test.
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(localeProvider) ?? const Locale('fr');
        return MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: locale,
          supportedLocales: supportedLocales,
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
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

  group('ProfilePage — en-tête', () {
    testWidgets('titre "Mon profil" affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Mon profil'), findsOneWidget);
    });

    testWidgets('nom complet + email affichés depuis le profil chargé', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()
        ..seed(_makeProfile(fullName: 'Marie Martin'));
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('txt_profile_header_name')), findsOneWidget);
      expect(find.text('Marie Martin'), findsOneWidget);
      expect(find.byKey(const Key('txt_profile_header_email')), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('sans fullName — pas de nom affiché, email visible', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('txt_profile_header_name')), findsNothing);
      expect(find.byKey(const Key('txt_profile_header_email')), findsOneWidget);
    });

    testWidgets(
      'erreur de chargement du profil — fallback sur l\'email auth, pas de '
      'spinner bloquant',
      (tester) async {
        final repo = _FakeProfileRepository()..throwOnGet = true;
        final authRepo = _FakeAuthRepository(_passwordUser());
        await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
        await tester.pumpAndSettle();

        // Le hub reste utilisable : titre + tuiles visibles malgré l'échec
        // du chargement du profil.
        expect(find.text('Mon profil'), findsOneWidget);
        expect(find.text('test@example.com'), findsOneWidget);
        expect(find.byKey(const Key('tile_profile_details')), findsOneWidget);
      },
    );
  });

  group('ProfilePage — groupe Compte', () {
    testWidgets('tuile Informations personnelles présente et navigable', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Informations personnelles'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tile_profile_details')));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileDetailsPage), findsOneWidget);
      expect(find.text('Informations personnelles'), findsOneWidget);
      expect(find.byKey(const Key('field_full_name')), findsOneWidget);
    });

    testWidgets('compte email → tuile Changer le mot de passe présente', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile_change_password')), findsOneWidget);
      expect(find.text('Changer le mot de passe'), findsOneWidget);
    });

    testWidgets('compte Google → tuile Changer le mot de passe absente', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_googleUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile_change_password')), findsNothing);
    });

    testWidgets('compte Apple → tuile Changer le mot de passe absente', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_appleUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile_change_password')), findsNothing);
    });

    testWidgets('session anonyme → tuile Changer le mot de passe absente', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_anonUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile_change_password')), findsNothing);
    });

    testWidgets('tuile Changer le mot de passe → navigue et monte le form', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      final authRepo = _FakeAuthRepository(_passwordUser());
      await tester.pumpWidget(_buildPage(repo: repo, authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tile_change_password')));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordPage), findsOneWidget);
      expect(find.text('Changer le mot de passe'), findsOneWidget);
      expect(find.byKey(const Key('field_current_password')), findsOneWidget);
    });
  });

  group('ProfilePage — Préférences, Aide, À propos, Session', () {
    testWidgets('Apparence — sélecteur de thème présent et inchangé', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Apparence'), findsOneWidget);
      expect(find.byKey(const Key('segments_theme_mode')), findsOneWidget);
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

    testWidgets('Langue (FEAT-043) — sélecteur présent avec 3 options', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Langue'), findsOneWidget);
      expect(find.byKey(const Key('segments_locale')), findsOneWidget);
      // « Système » est aussi l'option du sélecteur de thème (Apparence) —
      // les deux sections l'utilisent, d'où 2 occurrences attendues.
      expect(find.text('Système'), findsNWidgets(2));
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('choisir « English » applique et persiste la langue', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('segments_locale')));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfilePage)),
      );
      expect(container.read(localeProvider), const Locale('en'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale'), 'en');

      // Effet observable immédiat : le titre de section lui-même est traduit
      // (preuve bout-en-bout, pas seulement l'état du provider).
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets('groupe Aide — tuile Nous contacter présente et navigable', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Aide'), findsOneWidget);
      expect(find.byKey(const Key('tile_support')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('tile_support')));
      await tester.tap(find.byKey(const Key('tile_support')));
      await tester.pumpAndSettle();

      expect(find.byType(SupportPage), findsOneWidget);
      expect(find.text('Nous contacter'), findsOneWidget);
      expect(find.byKey(const Key('field_support_subject')), findsOneWidget);
    });

    testWidgets('groupe Aide — tuiles légales présentes', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile_terms')), findsOneWidget);
      expect(find.byKey(const Key('tile_privacy')), findsOneWidget);
      expect(find.byKey(const Key('tile_legal')), findsOneWidget);
    });

    testWidgets('tile Mentions légales → navigue vers /legal', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('tile_legal')));
      await tester.tap(find.byKey(const Key('tile_legal')));
      await tester.pumpAndSettle();

      expect(find.text('page legal'), findsOneWidget);
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

    testWidgets('bouton Se déconnecter présent et inchangé', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_logout_profile')), findsOneWidget);
    });
  });

  group('ProfilePage — suppression de compte (FEAT-045)', () {
    testWidgets(
      'tuile Supprimer mon compte dans le groupe Compte (exigence stores) et navigable',
      (tester) async {
        final repo = _FakeProfileRepository()..seed(_makeProfile());
        await tester.pumpWidget(_buildPage(repo: repo));
        await tester.pumpAndSettle();

        final tile = find.byKey(const Key('tile_delete_account'));
        expect(tile, findsOneWidget);
        // Dans le groupe « Compte » : au-dessus du header « Apparence »
        // (l'ancienne section dédiée en fin de hub a été retirée).
        expect(find.text('Suppression du compte'), findsNothing);
        expect(
          tester.getTopLeft(tile).dy <
              tester.getTopLeft(find.text('Apparence')).dy,
          isTrue,
        );

        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(find.text('page suppression compte'), findsOneWidget);
      },
    );
  });

  group(
    'ProfilePage — upsell Pro (freemium MVP, subscriptionsEnabled=false)',
    () {
      testWidgets(
        'bannière « Passer à Pro » masquée par défaut (Env.subscriptionsEnabled '
        'est un bool.fromEnvironment figé à la compilation, même pattern que '
        'Env.isProd testé ci-dessus)',
        (tester) async {
          final repo = _FakeProfileRepository()..seed(_makeProfile());
          await tester.pumpWidget(_buildPage(repo: repo));
          await tester.pumpAndSettle();

          expect(find.text('Passer à Pro'), findsNothing);
        },
      );
    },
  );

  group('ProfilePage — ordre des groupes (décision 2026-07-07)', () {
    testWidgets('Compte → Apparence → Aide → À propos → Session', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      double headerY(String title) => tester.getTopLeft(find.text(title)).dy;

      expect(headerY('Compte') < headerY('Apparence'), isTrue);
      expect(headerY('Apparence') < headerY('Aide'), isTrue);
      expect(headerY('Aide') < headerY('À propos'), isTrue);
      expect(headerY('À propos') < headerY('Session'), isTrue);
    });

    testWidgets('groupe Aide — tuile FAQ en tête, navigue vers /faq', (
      tester,
    ) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      final faqTile = find.byKey(const Key('tile_faq'));
      expect(faqTile, findsOneWidget);
      // FAQ avant « Nous contacter » dans le groupe Aide.
      expect(
        tester.getTopLeft(faqTile).dy <
            tester.getTopLeft(find.byKey(const Key('tile_support'))).dy,
        isTrue,
      );

      await tester.ensureVisible(faqTile);
      await tester.tap(faqTile);
      await tester.pumpAndSettle();

      expect(find.text('page faq'), findsOneWidget);
    });
  });

  group('proUpsellVisible — bannière « Passer à Pro » du profil', () {
    test(
      'visible seulement si abonnements ouverts, hors app store, non payant',
      () {
        expect(
          proUpsellVisible(
            subscriptionsEnabled: true,
            storeApp: false,
            isPaid: false,
          ),
          isTrue,
        );
      },
    );

    test('app store → jamais visible, même abonnements ouverts', () {
      expect(
        proUpsellVisible(
          subscriptionsEnabled: true,
          storeApp: true,
          isPaid: false,
        ),
        isFalse,
      );
    });

    test('abonnements fermés ou déjà payant → masquée', () {
      expect(
        proUpsellVisible(
          subscriptionsEnabled: false,
          storeApp: false,
          isPaid: false,
        ),
        isFalse,
      );
      expect(
        proUpsellVisible(
          subscriptionsEnabled: true,
          storeApp: false,
          isPaid: true,
        ),
        isFalse,
      );
    });

    testWidgets('app store → aucune bannière « Passer à Pro » rendue', (
      tester,
    ) async {
      debugIsStoreAppOverride = true;
      addTearDown(() => debugIsStoreAppOverride = false);
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Passer à Pro'), findsNothing);
    });
  });
}

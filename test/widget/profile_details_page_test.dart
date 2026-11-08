/// Tests widget de [ProfileDetailsPage].
///
/// Couvre :
/// - Pré-remplissage des champs si profil existant
/// - Champs requis vides → messages inline après soumission
/// - Submit valide → controller appelé + SnackBar succès
/// - État erreur → message inline affiché
/// - État submitting → bouton désactivé avec indicateur
/// - Email affiché en lecture seule
/// - Chargement initial en erreur → bouton Réessayer
library;

import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/profile/application/profile_form_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/profile/domain/profile_form_state.dart';
import 'package:easyrent/features/profile/presentation/profile_details_page.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
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

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

LandlordProfile _makeProfile({
  String? fullName,
  String? phone,
  String? address,
  String? email = 'test@example.com',
}) => LandlordProfile(
  id: 'uid-1',
  email: email,
  fullName: fullName,
  phone: phone,
  address: address,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  rgpdConsentAt: DateTime(2024),
  rgpdConsentVersion: 'legacy-1',
);

/// Auth minimal — la page ne consulte que `currentUser`, pour le repli email
/// quand la copie Firestore est absente. Le reste n'est jamais appelé.
class _NoCurrentUserAuth implements AuthRepository {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildPage({
  required _FakeProfileRepository repo,
  ProfileFormState? initialFormState,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ProfileDetailsPage(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(_NoCurrentUserAuth()),
      if (initialFormState != null)
        profileFormControllerProvider.overrideWith(
          (ref) => ProfileFormController(ref)..state = initialFormState,
        ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileDetailsPage — smoke tests', () {
    testWidgets('titre "Informations personnelles" affiché', (tester) async {
      final repo = _FakeProfileRepository()..seed(_makeProfile());
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Informations personnelles'), findsOneWidget);
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

    testWidgets('un email null NE casse PAS la page (régression staging)', (
      tester,
    ) async {
      // `email` était `required String` : un doc `landlords` portant
      // `email: null` faisait échouer `fromJson`, et l'écran entier tombait sur
      // « Impossible de charger le profil » — sans autre issue que Réessayer,
      // qui échouait pareil. Cas réel : compte issu du parcours « essai sans
      // compte », dont l'upgrade ne renseignait pas l'email.
      final repo = _FakeProfileRepository()..seed(_makeProfile(email: null));
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      // Le formulaire est rendu : `asyncProfile.when` a pris la branche `data`
      // et non `error` — les deux s'excluent, donc c'est la preuve directe que
      // l'écran ne tombe plus en erreur.
      expect(find.byKey(const Key('field_full_name')), findsOneWidget);
      expect(find.byKey(const Key('field_email_readonly')), findsOneWidget);
      expect(find.byKey(const Key('btn_save_profile')), findsOneWidget);
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
    // Submit valide
    // -----------------------------------------------------------------------
    testWidgets(
      'submit valide — repo.update appelé, snackbar succès affichée',
      (tester) async {
        final repo = _FakeProfileRepository()..seed(_makeProfile());
        await tester.pumpWidget(_buildPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field_full_name')),
          'Jean Dupont',
        );
        await tester.enterText(
          find.byKey(const Key('field_address')),
          '1 rue Test\n75000 Paris',
        );
        await tester.tap(find.byKey(const Key('btn_save_profile')));
        await tester.pumpAndSettle();

        expect(repo.lastFullName, 'Jean Dupont');
        expect(repo.lastAddress, '1 rue Test\n75000 Paris');
        expect(find.text('Profil mis à jour'), findsOneWidget);
      },
    );

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
            reason: ProfileFormErrorReason.unexpected,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le message exact est résolu via AppLocalizations (FEAT-043) ; on
      // vérifie juste qu'un texte d'erreur est bien rendu inline.
      final errorFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.style?.color != null &&
            (widget.data?.isNotEmpty ?? false) &&
            widget.key == null,
      );
      expect(errorFinder, findsWidgets);
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
}

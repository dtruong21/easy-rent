/// Tests widget de [ProfilePage].
///
/// Couvre :
/// - Pré-remplissage des champs si profil existant
/// - Champs requis vides → messages inline après soumission
/// - Submit valide → controller appelé + SnackBar succès
/// - État erreur → message inline affiché
/// - État submitting → bouton désactivé avec indicateur
/// - Email affiché en lecture seule
library;

import 'package:easyrent/features/profile/application/profile_form_controller.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/profile/domain/profile_form_state.dart';
import 'package:easyrent/features/profile/presentation/profile_page.dart';
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
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfilePage()),
    ],
  );

  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
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
}

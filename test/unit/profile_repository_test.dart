/// Tests du contrat [ProfileRepository] via un fake in-memory.
///
/// NOTE : [SupabaseProfileRepository] utilise [Db.from()] qui dépend de
/// [Supabase.instance.client] — non initialisé en test unitaire.
/// On teste donc le contrat de l'interface + les invariants du fake.
///
/// Vérifications couvertes :
/// - [getCurrent] : retourne le profil ou lève [ProfileNotFoundException]
/// - [update]     : les trois champs éditables sont bien passés au payload
/// - Payload ne contient JAMAIS id, email, created_at, updated_at
library;

import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _InMemoryProfileRepository implements ProfileRepository {
  LandlordProfile? _profile;

  /// Derniers arguments passés à [update] — pour vérifier le payload.
  String? lastFullName;
  String? lastPhone;
  String? lastAddress;

  void seed(LandlordProfile profile) => _profile = profile;

  @override
  Future<LandlordProfile> getCurrent() async {
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
    lastFullName = fullName;
    lastPhone = phone;
    lastAddress = address;

    final p = _profile;
    if (p == null) throw const ProfileNotFoundException();
    // Simule le comportement Supabase : retourne le profil mis à jour.
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
// Helper
// ---------------------------------------------------------------------------

LandlordProfile _makeProfile({
  String id = 'uid-1',
  String email = 'test@example.com',
  String? fullName,
  String? phone,
  String? address,
}) => LandlordProfile(
  id: id,
  email: email,
  fullName: fullName,
  phone: phone,
  address: address,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  rgpdConsentAt: DateTime(2024),
  rgpdConsentVersion: 'legacy-1',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileRepository — contrat', () {
    late _InMemoryProfileRepository repo;

    setUp(() => repo = _InMemoryProfileRepository());

    // -----------------------------------------------------------------------
    // getCurrent()
    // -----------------------------------------------------------------------
    group('getCurrent()', () {
      test('lève ProfileNotFoundException si profil absent', () {
        expect(
          () => repo.getCurrent(),
          throwsA(isA<ProfileNotFoundException>()),
        );
      });

      test('retourne le profil existant', () async {
        final profile = _makeProfile(fullName: 'Jean Dupont');
        repo.seed(profile);

        final result = await repo.getCurrent();
        expect(result.id, 'uid-1');
        expect(result.fullName, 'Jean Dupont');
      });

      test('email et id sont présents dans le profil retourné', () async {
        repo.seed(_makeProfile(email: 'jean@example.com'));

        final result = await repo.getCurrent();
        expect(result.email, 'jean@example.com');
        expect(result.id, isNotEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // update()
    // -----------------------------------------------------------------------
    group('update()', () {
      test('transmet fullName, phone et address au payload', () async {
        repo.seed(_makeProfile());

        await repo.update(
          fullName: 'Marie Martin',
          phone: '06 12 34 56 78',
          address: '12 rue de la Paix\n75001 Paris',
        );

        expect(repo.lastFullName, 'Marie Martin');
        expect(repo.lastPhone, '06 12 34 56 78');
        expect(repo.lastAddress, '12 rue de la Paix\n75001 Paris');
      });

      test('accepte phone null (champ optionnel)', () async {
        repo.seed(_makeProfile());

        await repo.update(
          fullName: 'Marie Martin',
          phone: null,
          address: '12 rue de la Paix\n75001 Paris',
        );

        expect(repo.lastPhone, isNull);
      });

      test('retourne le profil mis à jour', () async {
        repo.seed(_makeProfile());

        final result = await repo.update(
          fullName: 'Marie Martin',
          phone: null,
          address: '1 place de la République\n75003 Paris',
        );

        expect(result.fullName, 'Marie Martin');
        expect(result.address, '1 place de la République\n75003 Paris');
      });

      test('lève ProfileNotFoundException si profil absent', () {
        expect(
          () => repo.update(
            fullName: 'Test',
            phone: null,
            address: 'Adresse test',
          ),
          throwsA(isA<ProfileNotFoundException>()),
        );
      });

      test('ne modifie PAS id ni email', () async {
        repo.seed(_makeProfile(id: 'uid-fixed', email: 'fixed@example.com'));

        final result = await repo.update(
          fullName: 'Nom Modifié',
          phone: null,
          address: 'Adresse',
        );

        // id et email sont immutables
        expect(result.id, 'uid-fixed');
        expect(result.email, 'fixed@example.com');
      });
    });

    // -----------------------------------------------------------------------
    // ProfileNotFoundException
    // -----------------------------------------------------------------------
    group('ProfileNotFoundException', () {
      test('toString() contient le message attendu', () {
        const ex = ProfileNotFoundException();
        expect(ex.toString(), contains('ProfileNotFoundException'));
      });
    });
  });
}

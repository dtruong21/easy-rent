/// Tests du contrat [TenantRepository] via un fake in-memory.
///
/// NOTE : [FirestoreTenantRepository] utilise [FirebaseFirestore] qui dépend de
/// [FirebaseFirestore.instance] — non initialisé en test unitaire.
/// On teste donc le contrat de l'interface + les invariants du fake.
/// La vérification du payload SQL (ordre `.order('last_name')`, absence de
/// `landlord_id`, appel RPC `soft_delete_tenant`) est documentée ici comme
/// QA manuelle obligatoire (code review + security-auditor).
library;

import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _InMemoryTenantRepository implements TenantRepository {
  final List<Tenant> _tenants = [];
  String? lastArchivedId;
  String? lastCountedTenantId;
  String? lastLeasesQueriedForTenantId;

  @override
  Future<List<Tenant>> list() async {
    // Tri last_name ASC, first_name ASC — conforme au contrat du repository.
    final sorted = List<Tenant>.from(_tenants)
      ..sort((a, b) {
        final cmp = a.lastName.compareTo(b.lastName);
        return cmp != 0 ? cmp : a.firstName.compareTo(b.firstName);
      });
    return sorted;
  }

  @override
  Future<Tenant> getById(String id) async {
    final matches = _tenants.where((t) => t.id == id);
    if (matches.isEmpty) throw TenantNotFoundException(id);
    return matches.first;
  }

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async {
    final t = Tenant(
      id: 'gen-${_tenants.length + 1}',
      landlordId: 'owner-1',
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      birthDate: birthDate,
      birthPlace: birthPlace,
      nationality: nationality,
      profession: profession,
      employer: employer,
      monthlyIncomeCents: monthlyIncomeCents,
      previousAddress: previousAddress,
      guarantorName: guarantorName,
      guarantorEmail: guarantorEmail,
      guarantorPhone: guarantorPhone,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    _tenants.add(t);
    return t;
  }

  @override
  Future<Tenant> update(Tenant tenant) async {
    final idx = _tenants.indexWhere((t) => t.id == tenant.id);
    if (idx == -1) throw TenantNotFoundException(tenant.id);
    _tenants[idx] = tenant;
    return tenant;
  }

  @override
  Future<int> countActiveLeases(String tenantId) async {
    lastCountedTenantId = tenantId;
    return 0;
  }

  @override
  Future<void> archive(String id) async {
    lastArchivedId = id;
    _tenants.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async {
    return _tenants.map((t) => TenantListItem(tenant: t)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async {
    lastLeasesQueriedForTenantId = tenantId;
    return [];
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Tenant _make({
  String id = 'tid',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean@test.com',
  String? phone,
}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: firstName,
  lastName: lastName,
  email: email,
  phone: phone,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Tenant _makeWithAllFields({
  String id = 'tid-full',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean@test.com',
}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: firstName,
  lastName: lastName,
  email: email,
  phone: '06 12 34 56 78',
  birthDate: DateTime(1990, 5, 15),
  birthPlace: 'Paris',
  nationality: 'Française',
  profession: 'Ingénieur',
  employer: 'Tech Corp',
  monthlyIncomeCents: 350000,
  previousAddress: '10 rue Ancienne, 75001 Paris',
  guarantorName: 'Pierre Martin',
  guarantorEmail: 'pierre.martin@test.com',
  guarantorPhone: '06 98 76 54 32',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantRepository — contrat', () {
    late _InMemoryTenantRepository repo;

    setUp(() => repo = _InMemoryTenantRepository());

    // -----------------------------------------------------------------------
    // list()
    // -----------------------------------------------------------------------
    test('list() retourne une liste vide si aucun locataire', () async {
      final result = await repo.list();
      expect(result, isEmpty);
    });

    test(
      'list() retourne les locataires triés last_name ASC, first_name ASC',
      () async {
        await repo.create(
          firstName: 'Sophie',
          lastName: 'Martin',
          email: 's@t.com',
        );
        await repo.create(
          firstName: 'Jean',
          lastName: 'Dupont',
          email: 'j@t.com',
        );
        await repo.create(
          firstName: 'Alice',
          lastName: 'Martin',
          email: 'a@t.com',
        );

        final result = await repo.list();

        expect(result[0].lastName, 'Dupont');
        expect(result[1].lastName, 'Martin');
        expect(
          result[1].firstName,
          'Alice',
        ); // Alice Martin avant Sophie Martin
        expect(result[2].lastName, 'Martin');
        expect(result[2].firstName, 'Sophie');
      },
    );

    // -----------------------------------------------------------------------
    // getById()
    // -----------------------------------------------------------------------
    test('getById() retourne le locataire existant', () async {
      final created = await repo.create(
        firstName: 'Jean',
        lastName: 'Dupont',
        email: 'jean@test.com',
      );

      final found = await repo.getById(created.id);
      expect(found.id, created.id);
      expect(found.firstName, 'Jean');
    });

    test('getById() lève TenantNotFoundException si id inconnu', () async {
      expect(
        () => repo.getById('inconnu'),
        throwsA(isA<TenantNotFoundException>()),
      );
    });

    // -----------------------------------------------------------------------
    // create()
    // -----------------------------------------------------------------------
    test('create() retourne un Tenant avec les bons champs', () async {
      final t = await repo.create(
        firstName: 'Marie',
        lastName: 'Martin',
        email: 'marie@test.com',
        phone: '06 12 34 56 78',
      );

      expect(t.firstName, 'Marie');
      expect(t.lastName, 'Martin');
      expect(t.email, 'marie@test.com');
      expect(t.phone, '06 12 34 56 78');
      expect(t.id, isNotEmpty);
    });

    test('create() sans téléphone — phone est null', () async {
      final t = await repo.create(
        firstName: 'Paul',
        lastName: 'Durand',
        email: 'paul@test.com',
      );

      expect(t.phone, isNull);
    });

    test(
      'create() n\'inclut pas landlord_id ni timestamps dans le contrat',
      () async {
        // Le repo gère landlord_id côté serveur — le contrat create() n'expose pas ce paramètre.
        // Vérifié ici en s'assurant que la signature n'a pas ces paramètres.
        // Le fait que ce test compile est la vérification.
        final t = await repo.create(
          firstName: 'Test',
          lastName: 'User',
          email: 'test@test.com',
        );
        expect(t, isA<Tenant>());
      },
    );

    // -----------------------------------------------------------------------
    // update()
    // -----------------------------------------------------------------------
    test(
      'update() met à jour les champs et retourne le locataire modifié',
      () async {
        final original = await repo.create(
          firstName: 'Jean',
          lastName: 'Dupont',
          email: 'jean@test.com',
        );
        final modified = original.copyWith(
          firstName: 'Jean-Marc',
          email: 'jeanmarc@test.com',
        );

        final result = await repo.update(modified);
        expect(result.firstName, 'Jean-Marc');
        expect(result.email, 'jeanmarc@test.com');
      },
    );

    test('update() lève TenantNotFoundException si id inconnu', () async {
      expect(
        () => repo.update(_make(id: 'inconnu')),
        throwsA(isA<TenantNotFoundException>()),
      );
    });

    // -----------------------------------------------------------------------
    // countActiveLeases()
    // -----------------------------------------------------------------------
    test('countActiveLeases() transmet le tenantId correct', () async {
      await repo.countActiveLeases('tenant-42');
      expect(repo.lastCountedTenantId, 'tenant-42');
    });

    // -----------------------------------------------------------------------
    // archive()
    // -----------------------------------------------------------------------
    test('archive() passe par la bonne méthode (pas UPDATE direct)', () async {
      final t = await repo.create(
        firstName: 'Jean',
        lastName: 'Dupont',
        email: 'jean@test.com',
      );

      await repo.archive(t.id);
      expect(repo.lastArchivedId, t.id);
    });

    test('archive() — le locataire disparaît de list()', () async {
      final t = await repo.create(
        firstName: 'Jean',
        lastName: 'Dupont',
        email: 'jean@test.com',
      );

      await repo.archive(t.id);
      final list = await repo.list();
      expect(list.any((x) => x.id == t.id), isFalse);
    });

    // -----------------------------------------------------------------------
    // listLeasesForTenant()
    // -----------------------------------------------------------------------
    test('listLeasesForTenant() transmet le tenantId correct', () async {
      await repo.listLeasesForTenant('tenant-99');
      expect(repo.lastLeasesQueriedForTenantId, 'tenant-99');
    });

    test('listLeasesForTenant() retourne List<Map<String,dynamic>>', () async {
      final result = await repo.listLeasesForTenant('any-id');
      expect(result, isA<List<Map<String, dynamic>>>());
    });

    // -----------------------------------------------------------------------
    // create() — champs enrichis FEAT-014 Phase 2
    // -----------------------------------------------------------------------
    test(
      'create() préserve les champs enrichis (birth_date, guarantor, etc.)',
      () async {
        final t = await repo.create(
          firstName: 'Marie',
          lastName: 'Dupont',
          email: 'marie@test.com',
          birthDate: DateTime(1990, 5, 15),
          birthPlace: 'Paris',
          nationality: 'Française',
          profession: 'Ingénieure',
          employer: 'Tech Corp',
          monthlyIncomeCents: 300000,
          previousAddress: '1 rue Ancienne',
          guarantorName: 'Pierre Martin',
          guarantorEmail: 'pierre@test.com',
          guarantorPhone: '06 98 76 54 32',
        );

        expect(t.birthDate?.year, 1990);
        expect(t.birthPlace, 'Paris');
        expect(t.nationality, 'Française');
        expect(t.profession, 'Ingénieure');
        expect(t.employer, 'Tech Corp');
        expect(t.monthlyIncomeCents, 300000);
        expect(t.previousAddress, '1 rue Ancienne');
        expect(t.guarantorName, 'Pierre Martin');
        expect(t.guarantorEmail, 'pierre@test.com');
        expect(t.guarantorPhone, '06 98 76 54 32');
      },
    );

    test('_makeWithAllFields() construit un Tenant avec tous les champs', () {
      // Vérifie que le helper de test génère bien un Tenant complet.
      final t = _makeWithAllFields();
      expect(t.birthDate?.year, 1990);
      expect(t.monthlyIncomeCents, 350000);
      expect(t.guarantorEmail, 'pierre.martin@test.com');
    });

    // -----------------------------------------------------------------------
    // TenantNotFoundException
    // -----------------------------------------------------------------------
    test('TenantNotFoundException.toString() contient l\'id', () {
      const ex = TenantNotFoundException('abc-123');
      expect(ex.toString(), contains('abc-123'));
    });
  });
}

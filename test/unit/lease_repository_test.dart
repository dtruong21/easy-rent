/// Tests du contrat [LeaseRepository] via un fake in-memory.
///
/// NOTE : [SupabaseLeaseRepository] utilise [Db.from()] qui dépend de
/// [Supabase.instance.client] — non initialisé en test unitaire.
/// On teste donc le contrat de l'interface + les invariants du fake.
/// La vérification du payload SQL (absence de `landlord_id`/`status`/timestamps,
/// appel RPC `soft_delete_lease`, filtre `status='active'` pour close) est
/// documentée ici comme QA manuelle obligatoire (code review + security-auditor).
library;

import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _InMemoryLeaseRepository implements LeaseRepository {
  final List<Lease> _leases = [];
  String? lastArchivedId;
  String? lastClosedId;
  DateTime? lastCloseDate;

  @override
  Future<List<LeaseListItem>> listForDisplay() async {
    // Tri status ASC puis start_date DESC.
    final sorted = List<Lease>.from(_leases)
      ..sort((a, b) {
        final cmp = a.status.name.compareTo(b.status.name);
        return cmp != 0 ? cmp : b.startDate.compareTo(a.startDate);
      });
    return sorted
        .map(
          (l) => LeaseListItem(
            lease: l,
            propertyName: 'Bien ${l.propertyId}',
            tenantDisplayName: 'Locataire ${l.tenantId}',
          ),
        )
        .toList();
  }

  @override
  Future<Lease> getById(String id) async {
    final matches = _leases.where((l) => l.id == id);
    if (matches.isEmpty) throw LeaseNotFoundException(id);
    return matches.first;
  }

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
  }) async {
    final l = Lease(
      id: 'gen-${_leases.length + 1}',
      landlordId: 'owner-1',
      propertyId: propertyId,
      tenantId: tenantId,
      rentAmountCents: rentAmountCents,
      chargesAmountCents: chargesAmountCents,
      startDate: startDate,
      endDate: endDate,
      status: LeaseStatus.active,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    _leases.add(l);
    return l;
  }

  @override
  Future<Lease> update(Lease lease) async {
    final idx = _leases.indexWhere((l) => l.id == lease.id);
    if (idx == -1) throw LeaseNotFoundException(lease.id);
    _leases[idx] = lease;
    return lease;
  }

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async {
    final idx = _leases.indexWhere(
      (l) => l.id == id && l.status == LeaseStatus.active,
    );
    if (idx == -1) throw LeaseAlreadyClosedException(id);
    lastClosedId = id;
    lastCloseDate = effectiveEndDate;
    final closed = _leases[idx].copyWith(
      status: LeaseStatus.terminated,
      endDate: effectiveEndDate,
    );
    _leases[idx] = closed;
    return closed;
  }

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async {
    return _leases.any(
      (l) =>
          l.propertyId == propertyId &&
          l.status == LeaseStatus.active &&
          l.deletedAt == null &&
          l.id != excludeLeaseId,
    );
  }

  @override
  Future<void> archive(String id) async {
    lastArchivedId = id;
    _leases.removeWhere((l) => l.id == id);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  String id = 'l1',
  String propertyId = 'p1',
  String tenantId = 't1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? startDate,
  DateTime? endDate,
}) {
  return Lease(
    id: id,
    landlordId: 'lld',
    propertyId: propertyId,
    tenantId: tenantId,
    rentAmountCents: 85000,
    chargesAmountCents: 5000,
    startDate: startDate ?? DateTime(2024, 1, 1),
    endDate: endDate,
    status: status,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _InMemoryLeaseRepository repo;

  setUp(() => repo = _InMemoryLeaseRepository());

  group('create', () {
    test('crée un bail avec status active par défaut', () async {
      final lease = await repo.create(
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 85000,
        chargesAmountCents: 5000,
        startDate: DateTime(2024, 1, 1),
      );
      expect(lease.status, LeaseStatus.active);
      expect(lease.rentAmountCents, 85000);
      expect(lease.chargesAmountCents, 5000);
    });

    test('crée avec end_date optionnelle', () async {
      final lease = await repo.create(
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 85000,
        chargesAmountCents: 0,
        startDate: DateTime(2024, 1, 1),
        endDate: DateTime(2024, 12, 31),
      );
      expect(lease.endDate, DateTime(2024, 12, 31));
    });

    test('crée sans end_date → null (CDI)', () async {
      final lease = await repo.create(
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 1000,
        chargesAmountCents: 0,
        startDate: DateTime(2024, 1, 1),
      );
      expect(lease.endDate, isNull);
    });
  });

  group('getById', () {
    test('retourne le bail si trouvé', () async {
      repo._leases.add(_makeLease(id: 'l42'));
      final lease = await repo.getById('l42');
      expect(lease.id, 'l42');
    });

    test('lève LeaseNotFoundException si introuvable', () async {
      expect(
        () => repo.getById('inexistant'),
        throwsA(isA<LeaseNotFoundException>()),
      );
    });
  });

  group('update', () {
    test('met à jour le bail', () async {
      repo._leases.add(_makeLease(id: 'l1'));
      final updated = _makeLease(id: 'l1', propertyId: 'p2');
      final result = await repo.update(updated);
      expect(result.propertyId, 'p2');
    });

    test('lève LeaseNotFoundException si id inconnu', () async {
      expect(
        () => repo.update(_makeLease(id: 'inconnu')),
        throwsA(isA<LeaseNotFoundException>()),
      );
    });
  });

  group('close', () {
    test('clôture un bail actif → status terminated', () async {
      repo._leases.add(_makeLease(id: 'l1', status: LeaseStatus.active));
      final result = await repo.close(
        'l1',
        effectiveEndDate: DateTime(2024, 6),
      );
      expect(result.status, LeaseStatus.terminated);
      expect(result.endDate, DateTime(2024, 6));
    });

    test('lève LeaseAlreadyClosedException si bail déjà terminated', () async {
      repo._leases.add(_makeLease(id: 'l1', status: LeaseStatus.terminated));
      expect(
        () => repo.close('l1', effectiveEndDate: DateTime(2024, 6)),
        throwsA(isA<LeaseAlreadyClosedException>()),
      );
    });

    test('lève LeaseAlreadyClosedException si bail introuvable', () async {
      expect(
        () => repo.close('inexistant', effectiveEndDate: DateTime(2024, 6)),
        throwsA(isA<LeaseAlreadyClosedException>()),
      );
    });
  });

  group('hasOtherActiveLeaseOnProperty', () {
    test('pas d\'autre bail actif → false', () async {
      repo._leases.add(
        _makeLease(id: 'l1', propertyId: 'p1', status: LeaseStatus.active),
      );
      final result = await repo.hasOtherActiveLeaseOnProperty(
        'p1',
        excludeLeaseId: 'l1',
      );
      expect(result, isFalse);
    });

    test('bail actif sur même property (sans exclusion) → true', () async {
      repo._leases.add(
        _makeLease(id: 'l1', propertyId: 'p1', status: LeaseStatus.active),
      );
      final result = await repo.hasOtherActiveLeaseOnProperty('p1');
      expect(result, isTrue);
    });

    test(
      'bail actif sur même property (avec exclusion de lui-même) → false',
      () async {
        repo._leases.add(
          _makeLease(id: 'l1', propertyId: 'p1', status: LeaseStatus.active),
        );
        final result = await repo.hasOtherActiveLeaseOnProperty(
          'p1',
          excludeLeaseId: 'l1',
        );
        expect(result, isFalse);
      },
    );

    test('deux baux actifs — exclure l\'un → true pour l\'autre', () async {
      repo._leases.add(
        _makeLease(id: 'l1', propertyId: 'p1', status: LeaseStatus.active),
      );
      repo._leases.add(
        _makeLease(id: 'l2', propertyId: 'p1', status: LeaseStatus.active),
      );
      final result = await repo.hasOtherActiveLeaseOnProperty(
        'p1',
        excludeLeaseId: 'l1',
      );
      expect(result, isTrue);
    });
  });

  group('archive (soft-delete via RPC)', () {
    test('archive enregistre l\'id', () async {
      repo._leases.add(_makeLease(id: 'l1'));
      await repo.archive('l1');
      expect(repo.lastArchivedId, 'l1');
    });
  });

  group('listForDisplay', () {
    test('liste vide → []', () async {
      final result = await repo.listForDisplay();
      expect(result, isEmpty);
    });

    test('tri : active avant terminated', () async {
      repo._leases.add(
        _makeLease(id: 'l-terminated', status: LeaseStatus.terminated),
      );
      repo._leases.add(_makeLease(id: 'l-active', status: LeaseStatus.active));
      final result = await repo.listForDisplay();
      // "active" < "terminated" alphabétiquement
      expect(result.first.lease.status, LeaseStatus.active);
    });
  });
}

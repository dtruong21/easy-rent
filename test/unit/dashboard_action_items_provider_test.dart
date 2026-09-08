// test/unit/dashboard_action_items_provider_test.dart
import 'package:easyrent/features/dashboard/application/dashboard_action_items_provider.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLeasesNotifier extends LeasesListNotifier {
  _FakeLeasesNotifier(this._items);
  final List<LeaseListItem> _items;
  @override
  Future<List<LeaseListItem>> build() async => _items;
}

LeaseListItem _item({
  required String id,
  required LeaseStatus status,
  bool isLate = false,
  DateTime? endDate,
}) => LeaseListItem(
  lease: Lease(
    id: id,
    propertyId: 'p1',
    tenantId: 't1',
    rentAmountCents: 80000,
    chargesAmountCents: 0,
    nonRecoverableChargesCents: 0,
    startDate: DateTime(2020, 1, 1),
    endDate: endDate,
    status: status,
    landlordId: 'lord1',
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  propertyName: 'Bien $id',
  tenantDisplayName: 'Loc $id',
  isLate: isLate,
);

void main() {
  final soon = DateTime.now().add(const Duration(days: 20));
  final far = DateTime.now().add(const Duration(days: 200));

  ProviderContainer containerWith(List<LeaseListItem> items) =>
      ProviderContainer(
        overrides: [
          leasesListProvider.overrideWith(() => _FakeLeasesNotifier(items)),
        ],
      );

  test('partitionne retards et baux finissant, exclut terminés', () async {
    final c = containerWith([
      _item(
        id: 'late',
        status: LeaseStatus.active,
        isLate: true,
        endDate: soon,
      ),
      _item(id: 'ending', status: LeaseStatus.active, endDate: soon),
      _item(id: 'active_far', status: LeaseStatus.active, endDate: far),
      _item(id: 'terminated', status: LeaseStatus.terminated, endDate: soon),
    ]);
    addTearDown(c.dispose);
    // Laisse le leasesListProvider se résoudre.
    await c.read(leasesListProvider.future);

    final res = c.read(dashboardActionItemsProvider).value!;
    expect(res.late.map((i) => i.lease.id), ['late']);
    expect(res.ending.map((i) => i.lease.id), [
      'ending',
    ]); // pas 'late' (déjà en retard), pas 'terminated', pas 'active_far'
    expect(res.isEmpty, isFalse);
  });

  test('aucun item pertinent → isEmpty', () async {
    final c = containerWith([
      _item(id: 'active_far', status: LeaseStatus.active, endDate: far),
    ]);
    addTearDown(c.dispose);
    await c.read(leasesListProvider.future);
    expect(c.read(dashboardActionItemsProvider).value!.isEmpty, isTrue);
  });
}

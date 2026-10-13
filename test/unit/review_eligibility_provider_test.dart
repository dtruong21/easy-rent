/// Tests de [reviewEligibilityProvider] (FEAT-060) : le câblage session /
/// profil / biens / stockage / horloge ; la règle pure est couverte par
/// `review_eligibility_test.dart`.
library;

import 'package:easyrent/features/app_review/application/review_eligibility_provider.dart';
import 'package:easyrent/features/app_review/data/review_solicitation_storage.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/profile/application/landlord_profile_provider.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 9);

class _FakeProfileNotifier extends LandlordProfileNotifier {
  @override
  Future<LandlordProfile> build() async => LandlordProfile(
    id: 'uid-1',
    email: 'a@example.com',
    createdAt: _now.subtract(const Duration(days: 30)),
    updatedAt: _now,
    rgpdConsentAt: _now,
    rgpdConsentVersion: 'v1',
  );
}

class _FakePropsNotifier extends PropertiesListItemsNotifier {
  _FakePropsNotifier({this.fail = false});
  final bool fail;

  @override
  Future<List<PropertyListItem>> build() async {
    if (fail) throw StateError('Firestore indisponible');
    return [
      PropertyListItem(
        property: Property(
          id: 'p1',
          landlordId: 'uid-1',
          name: 'Bien',
          address: '1 rue',
          type: PropertyType.studio,
          createdAt: _now,
          updatedAt: _now,
        ),
      ),
    ];
  }
}

/// Jamais sollicité sur cet appareil (évite `SharedPreferences`).
class _NeverSolicitedStorage extends ReviewSolicitationStorage {
  @override
  Future<DateTime?> readLastSolicitedAt() async => null;
}

Future<bool> _eligible({
  SessionState session = SessionState.fullyAuthenticated,
  bool propsFail = false,
}) async {
  final c = ProviderContainer(
    overrides: [
      sessionStateProvider.overrideWithValue(session),
      landlordProfileProvider.overrideWith(_FakeProfileNotifier.new),
      propertiesListItemsProvider.overrideWith(
        () => _FakePropsNotifier(fail: propsFail),
      ),
      reviewSolicitationStorageProvider.overrideWithValue(
        _NeverSolicitedStorage(),
      ),
      reviewClockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(c.dispose);
  // Provider autoDispose : un listener le garde en vie jusqu'à la résolution.
  c.listen(reviewEligibilityProvider, (_, _) {});
  return c.read(reviewEligibilityProvider.future);
}

void main() {
  test('session non complète → false', () async {
    expect(await _eligible(session: SessionState.anonymous), isFalse);
    expect(await _eligible(session: SessionState.unauthenticated), isFalse);
  });

  test('une dépendance échoue → false (jamais de sollicitation)', () async {
    expect(await _eligible(propsFail: true), isFalse);
  });

  test('compte complet de 30 jours, 1 bien, jamais sollicité → true', () async {
    expect(await _eligible(), isTrue);
  });
}

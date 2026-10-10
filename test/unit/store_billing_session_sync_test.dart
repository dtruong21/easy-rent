/// Tests de [StoreBillingSessionSync] et de son câblage Riverpod (FEAT-044e) :
/// `logIn` pour un compte complet seulement, `logOut` en le quittant, appels
/// sérialisés, rien du tout quand l'achat intégré est coupé.
library;

import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/paid_plan/application/store_billing_session_sync.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_store_billing_service.dart';

const _full = SessionState.fullyAuthenticated;
const _anon = SessionState.anonymous;
const _out = SessionState.unauthenticated;

/// Repository d'auth réduit à `currentUser` (le reste n'est jamais appelé).
class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo(this.currentUser);

  @override
  final User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStoreBillingService fake;
  late StoreBillingSessionSync sync;

  setUp(() {
    fake = FakeStoreBillingService();
    sync = StoreBillingSessionSync(fake);
  });

  test('compte complet → configure une fois, puis logIn', () async {
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1']);
  });

  test('même compte répété → un seul logIn', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1']);
  });

  test('anonyme → jamais de logIn', () async {
    await sync.onSession(_anon, 'anon-1');
    expect(fake.calls, ['configure']);
  });

  test('non connecté au démarrage → pas de logOut', () async {
    await sync.onSession(_out, null);
    expect(fake.calls, ['configure']);
  });

  test('déconnexion après un compte complet → logOut', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_out, null);
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut']);
  });

  test('compte complet puis anonyme → logOut', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_anon, 'anon-1');
    expect(fake.calls.last, 'logOut');
  });

  test('changement de compte → logOut puis logIn du nouveau', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_out, null);
    await sync.onSession(_full, 'u2');
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut', 'logIn:u2']);
  });

  test('appels sérialisés : logOut attend la fin du logIn', () async {
    fake.logInGate = Completer<void>();
    final first = sync.onSession(_full, 'u1');
    final second = sync.onSession(_out, null);
    await pumpEventQueue();
    expect(fake.calls, ['configure', 'logIn:u1']);

    fake.logInGate!.complete();
    await Future.wait([first, second]);
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut']);
  });

  test('échec de logIn → aucune exception, l\'état suivant réessaie', () async {
    fake.logInError = StateError('réseau');
    await sync.onSession(_full, 'u1');
    fake.logInError = null;
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1', 'logIn:u1']);
  });

  group('storeBillingSessionSyncProvider', () {
    late StateProvider<SessionState> session;
    late ProviderContainer container;

    ProviderContainer build() {
      session = StateProvider<SessionState>((_) => _full);
      final c = ProviderContainer(
        overrides: [
          storeBillingServiceProvider.overrideWithValue(fake),
          sessionStateProvider.overrideWith((ref) => ref.watch(session)),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(MockUser(uid: 'u1', isEmailVerified: true)),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    tearDown(() => debugInAppPurchaseEnabledOverride = null);

    test('achat intégré coupé → aucun appel au service', () async {
      debugInAppPurchaseEnabledOverride = false;
      container = build();
      container.read(storeBillingSessionSyncProvider);
      await pumpEventQueue();
      expect(fake.calls, isEmpty);
    });

    test('achat intégré actif → logIn de l\'uid courant, logOut à la '
        'déconnexion', () async {
      debugInAppPurchaseEnabledOverride = true;
      container = build();
      container.read(storeBillingSessionSyncProvider);
      await pumpEventQueue();
      expect(fake.calls, ['configure', 'logIn:u1']);

      container.read(session.notifier).state = _out;
      await pumpEventQueue();
      expect(fake.calls.last, 'logOut');
    });
  });
}

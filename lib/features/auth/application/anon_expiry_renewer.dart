import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../data/auth_repository.dart';
import '../domain/session_state.dart';
import 'auth_session_provider.dart';

final _log = Logger('AnonExpiryRenewer');

/// Durée de la fenêtre d'expiration glissante (14 jours, BAILLAN-M1).
const Duration anonExpiryWindow = Duration(days: 14);

/// Throttle anti-spam : au plus 1 write Firestore par heure, même si
/// plusieurs signaux d'activité se produisent en rafale (boot + save
/// scénario immédiat, par exemple).
const Duration anonExpiryRenewThrottle = Duration(hours: 1);

/// Contrat testable pour l'écriture Firestore — permet l'injection d'un
/// horodatage déterministe en test sans dépendre de `FieldValue.serverTimestamp()`
/// (opaque côté client, `fake_cloud_firestore` le résout mais complique les
/// assertions sur la valeur exacte écrite).
abstract interface class AnonExpiryWriter {
  Future<void> renew(String uid, DateTime newExpiry);
}

class FirestoreAnonExpiryWriter implements AnonExpiryWriter {
  FirestoreAnonExpiryWriter(this._firestore);
  final FirebaseFirestore _firestore;

  @override
  Future<void> renew(String uid, DateTime newExpiry) async {
    await _firestore.doc('landlords/$uid').update({
      'anonExpiresAt': Timestamp.fromDate(newExpiry),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final anonExpiryWriterProvider = Provider<AnonExpiryWriter>(
  (ref) => FirestoreAnonExpiryWriter(ref.watch(firestoreProvider)),
);

/// Renouvelle `landlords/{uid}.anonExpiresAt` à `now + 14 jours` sur
/// activité meaningful d'une session anonyme (boot app, sauvegarde de
/// scénario). Throttle mémoire 1×/heure — voir [anonExpiryRenewThrottle].
///
/// No-op silencieux pour toute session non-anonyme (jamais de write).
class AnonExpiryRenewer extends Notifier<void> {
  DateTime? _lastRenewed;
  DateTime Function() _now = DateTime.now;

  @override
  void build() {}

  /// Permet l'injection d'une horloge déterministe en test (`fakeAsync` ou
  /// clock manuel). Jamais appelé en production (le défaut `DateTime.now`
  /// suffit).
  void debugSetClock(DateTime Function() now) => _now = now;

  Future<void> renewIfNeeded() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final sessionState = ref.read(sessionStateProvider);
    if (uid == null || sessionState != SessionState.anonymous) {
      return;
    }

    final now = _now();
    if (_lastRenewed != null &&
        now.difference(_lastRenewed!) < anonExpiryRenewThrottle) {
      return;
    }

    try {
      await ref
          .read(anonExpiryWriterProvider)
          .renew(uid, now.add(anonExpiryWindow));
      _lastRenewed = now;
      _log.info('anonExpiresAt renewed for uid=$uid');
    } catch (e, st) {
      _log.warning('anonExpiresAt renewal failed for uid=$uid', e, st);
    }
  }
}

final anonExpiryRenewerProvider = NotifierProvider<AnonExpiryRenewer, void>(
  AnonExpiryRenewer.new,
);

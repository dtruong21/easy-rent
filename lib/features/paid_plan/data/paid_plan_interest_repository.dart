import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';

final _log = Logger('PaidPlanInterestRepository');

abstract interface class PaidPlanInterestRepository {
  /// Enregistre (ou met à jour) l'intérêt du landlord connecté pour le
  /// Plan Pro. Idempotent : un second appel avec des `features` différentes
  /// fusionne (dédoublonne) plutôt que d'écraser.
  Future<void> markInterest({required List<String> features, String? email});
}

class FirestorePaidPlanInterestRepository
    implements PaidPlanInterestRepository {
  FirestorePaidPlanInterestRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<void> markInterest({
    required List<String> features,
    String? email,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError(
        'markInterest requires an authenticated user (uid == null).',
      );
    }
    _log.info('markInterest(features=$features)');

    final ref = _firestore.doc('paid_plan_interest/$uid');
    final existing = await ref.get();
    final existingFeatures =
        (existing.data()?['features'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        <String>[];
    final mergedFeatures = <String>{...existingFeatures, ...features}.toList();

    await ref.set({
      'features': mergedFeatures,
      'email': email,
      'notifyAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final paidPlanInterestRepositoryProvider = Provider<PaidPlanInterestRepository>(
  (ref) => FirestorePaidPlanInterestRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
  ),
);

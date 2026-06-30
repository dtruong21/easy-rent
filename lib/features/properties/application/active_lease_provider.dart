import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('ActiveLeaseProvider');

/// Retourne le loyer HC du bail actif d'un bien donné, ou null si vacant.
///
/// Query Firestore : `leases` where landlordId+propertyId+status=active+
/// deletedAt=null. Évite un import circulaire entre properties et leases.
final activeLeaseRentProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, propertyId) async {
    _log.info('activeLeaseRentProvider($propertyId)');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final qs = await FirebaseFirestore.instance
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('propertyId', isEqualTo: propertyId)
        .where('status', isEqualTo: 'active')
        .where('deletedAt', isEqualTo: null)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    final raw = qs.docs.first.data()['rentAmountCents'];
    return raw is int ? raw : null;
  },
);

/// Retourne l'identifiant du bail actif pour un bien donné, ou null si vacant.
final activeLeaseIdProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, propertyId) async {
      _log.info('activeLeaseIdProvider($propertyId)');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final qs = await FirebaseFirestore.instance
          .collection('leases')
          .where('landlordId', isEqualTo: uid)
          .where('propertyId', isEqualTo: propertyId)
          .where('status', isEqualTo: 'active')
          .where('deletedAt', isEqualTo: null)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) return null;
      return qs.docs.first.id;
    });

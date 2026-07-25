import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../../leases/domain/lease.dart';

final _log = Logger('PropertyLeasesProvider');

/// Liste des baux (actifs + terminés, non archivés) d'un bien — utilisée
/// pour le dropdown "Bail concerné (optionnel)" du formulaire dépense.
///
/// Requête directe Firestore (évite un import circulaire entre `expenses` et
/// `leases`, pattern déjà suivi par `active_lease_provider.dart` côté
/// `properties`). Triée `startDate DESC` (le bail le plus récent en premier).
final propertyLeasesProvider = FutureProvider.autoDispose
    .family<List<Lease>, String>((ref, propertyId) async {
      _log.info('fetch leases for property=$propertyId');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return const [];
      final qs = await ref
          .watch(firestoreProvider)
          .collection('leases')
          .where('landlordId', isEqualTo: uid)
          .where('propertyId', isEqualTo: propertyId)
          .where('deletedAt', isNull: true)
          .orderBy('startDate', descending: true)
          .limit(100)
          .get();
      return qs.docs
          .map(
            (d) =>
                Lease.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
          )
          .toList();
    });

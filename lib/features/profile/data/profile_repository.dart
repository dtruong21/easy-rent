import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../domain/landlord_profile.dart';

final _log = Logger('ProfileRepository');

abstract interface class ProfileRepository {
  /// Retourne le profil du landlord connecté (`landlords/{auth.uid}`).
  ///
  /// Les rules Firestore garantissent `request.auth.uid == uid` (read-self).
  Future<LandlordProfile> getCurrent();

  /// Met à jour fullName, phone, address. Les champs id, email,
  /// rgpdConsentAt, rgpdConsentVersion, createdAt, deletedAt sont
  /// IMMUTABLES via les rules.
  Future<LandlordProfile> update({
    required String? fullName,
    required String? phone,
    required String? address,
  });
}

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.doc('landlords/$uid');

  @override
  Future<LandlordProfile> getCurrent() async {
    final uid = _uid;
    if (uid == null) throw const ProfileNotFoundException();
    _log.info('getCurrent()');

    final snap = await _ref(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw const ProfileNotFoundException();
    }
    return LandlordProfile.fromJson(
      firestoreDocToSnakeJson(data, docId: snap.id),
    );
  }

  @override
  Future<LandlordProfile> update({
    required String? fullName,
    required String? phone,
    required String? address,
  }) async {
    final uid = _uid;
    if (uid == null) throw const ProfileNotFoundException();
    _log.info('update()');

    String? trimmed(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    // `updatedAt` n'est VOLONTAIREMENT pas écrit ici : le trigger serveur
    // `setUpdatedAtLandlords` (functions/src/triggers/set_updated_at.ts) s'en
    // charge, et c'est lui la source de vérité.
    //
    // L'écrire depuis le client cassait la sauvegarde du profil. Un
    // `FieldValue.serverTimestamp()` vaut `null` tant que le serveur n'a pas
    // confirmé (compensation de latence) ; la relecture juste en dessous
    // rendait alors un doc dont `updatedAt` était nul, or `LandlordProfile` le
    // déclare `required DateTime` → `fromJson` levait, la couche appelante
    // classait ça en « erreur inattendue » et l'utilisateur voyait
    // « Impossible de mettre à jour le profil ».
    //
    // Le piège : **l'écriture avait bel et bien réussi**. Seule la relecture
    // échouait. L'utilisateur enregistrait donc son profil à chaque tentative
    // en croyant l'inverse — signalé en recette sur staging (2026-08-11).
    final payload = <String, dynamic>{
      'fullName': trimmed(fullName),
      'phone': trimmed(phone),
      'address': trimmed(address),
    };
    final ref = _ref(uid);
    await ref.update(payload);

    final saved = await ref.get();
    final data = saved.data();
    if (!saved.exists || data == null) {
      throw const ProfileNotFoundException();
    }
    return LandlordProfile.fromJson(
      firestoreDocToSnakeJson(data, docId: saved.id),
    );
  }
}

class ProfileNotFoundException implements Exception {
  const ProfileNotFoundException();
  @override
  String toString() => 'ProfileNotFoundException: profil bailleur introuvable';
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return FirestoreProfileRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
  );
});

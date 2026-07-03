import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('SupportRepository');

abstract interface class SupportRepository {
  /// Écrit une demande de contact dans `support_requests/{auto}`.
  ///
  /// Create-only côté client (jamais relu, jamais listé — voir rules
  /// FEAT-025). [subject] et [message] doivent respecter les bornes
  /// validées côté [SupportController] ET côté rules (1..120 / 1..2000
  /// caractères).
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  });
}

class FirestoreSupportRepository implements SupportRepository {
  FirestoreSupportRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      // Bug d'appel : la section Support n'est montrée qu'à un utilisateur
      // pleinement authentifié (email présent).
      throw StateError('SupportRepository.submit requires a signed-in user.');
    }
    _log.info('submit() support request');

    await _firestore.collection('support_requests').add({
      'landlordId': user.uid,
      'email': user.email,
      'subject': subject,
      'message': message,
      'appVersion': appVersion,
      'appEnv': appEnv,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return FirestoreSupportRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';

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

  /// Écrit un avis (FEAT-060) dans `support_requests/{auto}` :
  /// `kind: 'feedback'`, [rating] 1-5, [comment] 0-2000 caractères (peut
  /// être vide), [platform] `web` / `ios` / `android`. Sujet fixe
  /// « Avis — {note}/5 ». Create-only, jamais relu.
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
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

  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('SupportRepository.submitFeedback requires a user.');
    }
    _log.info('submitFeedback() rating=$rating platform=$platform');

    await _firestore.collection('support_requests').add({
      'landlordId': user.uid,
      'email': user.email,
      'subject': 'Avis — $rating/5',
      'message': comment,
      'appVersion': appVersion,
      'appEnv': appEnv,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'kind': 'feedback',
      'rating': rating,
      'platform': platform,
    });
  }
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return FirestoreSupportRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
  );
});

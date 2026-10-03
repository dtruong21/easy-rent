import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import '../domain/documents_quota.dart';

final _log = Logger('DocumentsRepository');

const int _kMaxDocumentsPerList = 500;

/// Documents = fichiers utilisateur (bail signé, état des lieux, attestations,
/// justificatifs de dépense).
///
/// Architecture FEAT-019, étendue FEAT-041b :
/// - Upload Firebase Storage direct (Rules autorisent
///   `documents/{landlordId}/...`)
/// - Métadonnées Firestore via Callable `createDocument` v2 (valide lease
///   et/ou bien ownership + calcule legalHold depuis category — au moins un
///   de `leaseId`/`propertyId` requis, voir
///   `docs/plans/FEAT-041-depenses.md` § g)
/// - Download via signed URL générée côté serveur (`getDocumentDownloadUrl`)
/// - Soft-delete via Callable `softDeleteEntity` (refus si legalHold=true)
abstract interface class DocumentsRepository {
  Future<List<Document>> listForLease(String leaseId);

  Future<Document> getById(String id);

  /// Pipeline upload :
  /// 1. Génère un docId Firestore
  /// 2. Upload bytes vers `documents/{uid}/{docId}.{ext}` via Storage SDK
  /// 3. Appelle Callable `createDocument` v2 (valide lease et/ou propriété,
  ///    calcule legalHold) — voir `docs/plans/FEAT-041-depenses.md` § g)
  /// 4. Si étape 3 échoue, supprime le fichier Storage (best-effort rollback)
  ///
  /// [leaseId] et [propertyId] sont tous deux optionnels mais **au moins un
  /// des deux est requis** (validé côté serveur) — un justificatif de
  /// dépense (`expense_receipt`) peut n'avoir aucun bail.
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  });

  /// Soft-delete via Callable `softDeleteEntity` :
  /// - Refuse si `legalHold = true` (bail signé, EDL — rétention 5 ans)
  /// - Sinon soft-delete uniquement (fichier Storage conservé pour audit
  ///   — nettoyage P2 via cron Cloud Functions)
  Future<({String? storagePath, bool hardDeleted})> softDelete(String id);

  /// Met à jour la category. Les Rules Firestore interdisent l'update direct
  /// côté client (on bloque tout sur documents) — la mutation passe donc par la
  /// Callable `updateDocumentCategory`, qui recalcule `legalHold` et refuse un
  /// document déjà sous rétention légale.
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  });

  /// Génère une URL signée 5 min via Callable `getDocumentDownloadUrl`.
  Future<String> createSignedUrl(
    String documentId, {
    int expiresInSeconds = 300,
  });

  Future<DocumentsQuota> quotaForCurrentLandlord();
}

class FirestoreDocumentsRepository implements DocumentsRepository {
  FirestoreDocumentsRepository(
    this._firestore,
    this._auth,
    this._storage,
    this._functions,
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — document operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('documents');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
  );

  @override
  Future<List<Document>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .where('deletedAt', isNull: true)
        .orderBy('uploadedAt', descending: true)
        .limit(_kMaxDocumentsPerList)
        .get();
    return qs.docs
        .map(
          (d) =>
              Document.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Future<Document> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw DocumentNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw DocumentNotFoundException(id);
    }
    return Document.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    if (leaseId == null && propertyId == null) {
      throw ArgumentError(
        'upload() requires at least one of leaseId or propertyId',
      );
    }
    _log.info(
      'upload(leaseId=$leaseId, propertyId=$propertyId, filename=$filename, '
      'mimeType=$mimeType)',
    );
    final uid = _uid;
    final docRef = _col.doc(); // génère docId Firestore
    final docId = docRef.id;
    final ext = extensionFromMime(mimeType) ?? 'bin';
    final storagePath = 'documents/$uid/$docId.$ext';

    _log.fine('storagePath=$storagePath');
    onProgress?.call(0.0);

    final fileRef = _storage.ref(storagePath);

    // 1. Upload Storage avec progress tracking
    final uploadTask = fileRef.putData(
      bytes,
      SettableMetadata(contentType: mimeType),
    );
    uploadTask.snapshotEvents.listen((s) {
      if (s.totalBytes > 0 && onProgress != null) {
        onProgress(s.bytesTransferred / s.totalBytes);
      }
    });
    try {
      await uploadTask;
    } catch (e, st) {
      _log.severe('Storage upload failed', e, st);
      throw const DocumentUploadException('Upload du fichier échoué.');
    }

    _log.fine('storage upload OK docId=$docId');
    onProgress?.call(1.0);

    // 2. Callable createDocument (cross-entity validation + legalHold)
    try {
      await _callable('createDocument').call(<String, dynamic>{
        'leaseId': leaseId,
        'propertyId': propertyId,
        'category': category.sqlValue,
        'filename': filename,
        'storagePath': storagePath,
        'mimeType': mimeType,
        'sizeBytes': bytes.length,
      });
    } catch (e, st) {
      // Le rollback Storage est fait PAR LE SERVEUR : `createDocument` purge
      // l'objet sur tous ses motifs de refus. Le tenter ici serait un no-op —
      // `storage.rules` interdit le `delete` client sur `documents/**`.
      _log.severe(
        'createDocument callable failed (rollback storage côté serveur)',
        e,
        st,
      );
      rethrow;
    }

    // Note : la CF crée son propre docId via .doc() — celui-ci diffère de
    // notre docRef.id local. Pour récupérer le doc créé on relit la liste
    // récente. Solution propre : on lit le doc via getById(callableResult.documentId).
    // Pour l'instant on relit par leaseId + storagePath match (1 doc max).
    final snaps = await _col
        .where('landlordId', isEqualTo: uid)
        .where('storagePath', isEqualTo: storagePath)
        .limit(1)
        .get();
    if (snaps.docs.isEmpty) {
      throw const DocumentUploadException(
        'Document créé mais introuvable côté Firestore',
      );
    }
    final created = snaps.docs.first;
    _log.info('document inserted id=${created.id}');
    return Document.fromJson(
      firestoreDocToSnakeJson(created.data(), docId: created.id),
    );
  }

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async {
    _log.info('softDelete(id=$id)');

    // Lit le doc avant pour récupérer storagePath (remonté à l'UI) et
    // vérifier l'ownership. Le verdict legalHold, lui, vient du serveur.
    final snap = await _col.doc(id).get();
    if (!snap.exists) throw DocumentNotFoundException(id);
    final data = snap.data()!;
    if (data['landlordId'] != _uid) {
      throw DocumentNotFoundException(id);
    }
    final storagePath = data['storagePath'] as String?;

    final HttpsCallableResult<dynamic> res;
    try {
      res = await _callable(
        'softDeleteEntity',
      ).call(<String, dynamic>{'collection': 'documents', 'id': id});
    } on FirebaseFunctionsException catch (e) {
      if (e.message?.contains('document_under_legal_hold') == true) {
        // Cas attendu — propage le tuple avec hardDeleted=false pour informer l'UI
        return (storagePath: storagePath, hardDeleted: false);
      }
      rethrow;
    }

    // La suppression du fichier Storage est faite PAR LE SERVEUR, dans le
    // callable : `storage.rules` pose `allow delete: if false` sur
    // `documents/{landlordId}/**`, donc un delete depuis le client est
    // toujours refusé. Le tenter ici échouait silencieusement et laissait le
    // fichier dans le bucket à chaque suppression (coût + droit à l'effacement
    // RGPD non honoré). On se contente désormais de rapporter le verdict du
    // serveur. `storageDeleted=false` couvre deux cas : legalHold (fichier
    // conservé volontairement) ou échec de purge (logué `[orphan-document]`).
    final hardDeleted = (res.data as Map?)?['storageDeleted'] == true;
    _log.info('softDelete OK id=$id storageDeleted=$hardDeleted');
    return (storagePath: storagePath, hardDeleted: hardDeleted);
  }

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async {
    _log.info('updateCategory(id=$id, category=${newCategory.sqlValue})');
    // Rules Firestore bloquent l'update direct sur documents/{id} — tout passe
    // par la Callable `updateDocumentCategory`, qui revalide l'ownership,
    // recalcule `legalHold` depuis la nouvelle catégorie et refuse un document
    // déjà sous rétention (`document_under_legal_hold`).
    await _callable('updateDocumentCategory').call(<String, dynamic>{
      'documentId': id,
      'category': newCategory.sqlValue,
    });

    // Relit le document mis à jour (source de vérité serveur : legalHold +
    // updatedAt recalculés côté callable). getById valide ownership + non-supprimé.
    return getById(id);
  }

  @override
  Future<String> createSignedUrl(
    String documentId, {
    int expiresInSeconds = 300,
  }) async {
    _log.info('createSignedUrl(documentId=$documentId)');
    final res = await _callable(
      'getDocumentDownloadUrl',
    ).call(<String, dynamic>{'documentId': documentId});
    final url = (res.data as Map?)?['downloadUrl'] as String?;
    if (url == null) {
      throw StateError('getDocumentDownloadUrl did not return downloadUrl');
    }
    return url;
  }

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async {
    _log.info('quotaForCurrentLandlord()');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isNull: true)
        .get();
    var total = 0;
    for (final d in qs.docs) {
      final size = d.data()['sizeBytes'];
      if (size is int) total += size;
    }
    return DocumentsQuota(totalBytes: total);
  }
}

class DocumentNotFoundException implements Exception {
  const DocumentNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'DocumentNotFoundException: document $id introuvable';
}

class DocumentUploadException implements Exception {
  const DocumentUploadException(this.message);
  final String message;
  @override
  String toString() => 'DocumentUploadException: $message';
}

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return FirestoreDocumentsRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseStorage.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});

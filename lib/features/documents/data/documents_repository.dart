import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import '../domain/documents_quota.dart';

final _log = Logger('DocumentsRepository');
const _uuid = Uuid();

/// Garde-fou : on ne liste pas plus de [_kMaxDocumentsPerList] documents par
/// bail en une seule requête.
/// Cible utilisateur : 5–30 documents par bail en pratique.
/// Aligné sur le pattern des autres list queries (receipts, payments).
const int _kMaxDocumentsPerList = 500;

/// Contrat public du repository documents.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class DocumentsRepository {
  /// Liste tous les documents actifs d'un bail, triés par [uploaded_at DESC].
  Future<List<Document>> listForLease(String leaseId);

  /// Retourne un document par son [id].
  Future<Document> getById(String id);

  /// Upload un fichier dans le bucket `documents` puis insère la row DB.
  ///
  /// Génère un UUID côté client pour le [Document.id] et le chemin Storage.
  /// Si l'INSERT DB échoue, supprime le fichier Storage (best-effort rollback).
  ///
  /// [onProgress] : callback simulé (0.0 → 1.0) — Supabase SDK ne supporte pas
  /// le vrai progress natif pour `uploadBinary`.
  Future<Document> upload({
    required String leaseId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  });

  /// Soft-delete un document via la RPC `soft_delete_document`.
  ///
  /// Si la RPC retourne `hard_deleted = true`, appelle également
  /// `storage.from('documents').remove([storagePath])` (best-effort).
  ///
  /// Retourne un tuple `(storagePath, hardDeleted)` pour informer l'UI.
  Future<({String? storagePath, bool hardDeleted})> softDelete(String id);

  /// Met à jour la [category] d'un document existant.
  ///
  /// Seul [category] est UPDATE-able — les autres colonnes sont protégées
  /// par le trigger `tr_01b_protect_immutable_documents`.
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  });

  /// Génère une URL signée (5 min) pour accéder au fichier dans Storage.
  ///
  /// [expiresInSeconds] : TTL par défaut 300s (aligné FEAT-007).
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  });

  /// Calcule le quota de stockage utilisé par le bailleur courant.
  ///
  /// Somme `size_bytes` WHERE `landlord_id = auth.uid() AND deleted_at IS NULL`.
  Future<DocumentsQuota> quotaForCurrentLandlord();
}

/// Implémentation Supabase du [DocumentsRepository].
class SupabaseDocumentsRepository implements DocumentsRepository {
  const SupabaseDocumentsRepository();

  @override
  Future<List<Document>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final rows = await Db.from('documents')
        .select()
        .eq('lease_id', leaseId)
        .order('uploaded_at', ascending: false)
        .limit(_kMaxDocumentsPerList);
    return rows.map((r) => Document.fromJson(r)).toList();
  }

  @override
  Future<Document> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('documents').select().eq('id', id).limit(1);
    if (rows.isEmpty) throw DocumentNotFoundException(id);
    return Document.fromJson(rows.first);
  }

  @override
  Future<Document> upload({
    required String leaseId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    _log.info(
      'upload(leaseId=$leaseId, filename=$filename, mimeType=$mimeType)',
    );

    final docId = _uuid.v4();
    final ext = extensionFromMime(mimeType) ?? 'bin';
    final relativePath = 'documents/$docId.$ext';
    final storagePath = Db.storagePath(relativePath);

    _log.fine('storagePath=$storagePath');

    // Simule progress 0% avant upload (Supabase uploadBinary ne supporte pas
    // onProgress natif côté Dart — vraie progress = P1)
    onProgress?.call(0.0);

    // 1. Upload Storage
    await Supabase.instance.client.storage
        .from('documents')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    _log.fine('storage upload OK docId=$docId');
    onProgress?.call(1.0);

    // 2. INSERT DB
    final landlordId = Supabase.instance.client.auth.currentUser?.id;
    if (landlordId == null) {
      // Rollback Storage best-effort si l'utilisateur s'est déconnecté entre-temps
      await _removeStorageObject(storagePath);
      throw const DocumentUploadException('Utilisateur non authentifié.');
    }

    try {
      final row = await Db.from('documents')
          .insert({
            'id': docId,
            'landlord_id': landlordId,
            'lease_id': leaseId,
            'category': category.sqlValue,
            'filename': filename,
            'storage_path': storagePath,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select()
          .single();
      _log.info('document inserted id=$docId');
      return Document.fromJson(row);
    } catch (e, st) {
      _log.severe('INSERT documents failed, rolling back storage', e, st);
      await _removeStorageObject(storagePath);
      rethrow;
    }
  }

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async {
    _log.info('softDelete(id=$id)');

    final result = await Db.rpc('soft_delete_document', params: {'p_id': id});

    if (result == null || (result as List).isEmpty) {
      throw DocumentNotFoundException(id);
    }

    final row = result.first as Map<String, dynamic>;
    final hardDeleted = row['hard_deleted'] as bool? ?? false;
    final path = row['storage_path'] as String?;

    if (hardDeleted && path != null) {
      _log.info('hard-deleting storage object path=$path');
      await _removeStorageObject(path);
    } else {
      _log.info(
        'legal_hold ON — storage object conservé pour obligation légale',
      );
    }

    return (storagePath: path, hardDeleted: hardDeleted);
  }

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async {
    _log.info('updateCategory(id=$id, category=${newCategory.sqlValue})');
    final row = await Db.from(
      'documents',
    ).update({'category': newCategory.sqlValue}).eq('id', id).select().single();
    return Document.fromJson(row);
  }

  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async {
    _log.info('createSignedUrl(storagePath=$storagePath)');
    return Supabase.instance.client.storage
        .from('documents')
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async {
    _log.info('quotaForCurrentLandlord()');
    final landlordId = Supabase.instance.client.auth.currentUser?.id;
    if (landlordId == null) {
      return const DocumentsQuota(totalBytes: 0);
    }

    final rows = await Db.from('documents')
        .select('size_bytes')
        .eq('landlord_id', landlordId)
        .isFilter('deleted_at', null);

    final totalBytes = (rows as List).fold<int>(
      0,
      (acc, row) => acc + ((row as Map<String, dynamic>)['size_bytes'] as int),
    );

    return DocumentsQuota(totalBytes: totalBytes);
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  /// Supprime un objet dans Storage (best-effort — log si échec, ne re-throw pas).
  Future<void> _removeStorageObject(String path) async {
    try {
      await Supabase.instance.client.storage.from('documents').remove([path]);
      _log.fine('storage remove OK path=$path');
    } catch (e, st) {
      // Orphan toléré au MVP — nettoyage P2 via cron + grep logs
      _log.severe(
        '[orphan-document] path=$path — storage.remove a échoué',
        e,
        st,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception levée quand un document est introuvable (RLS ou id inconnu).
class DocumentNotFoundException implements Exception {
  const DocumentNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'DocumentNotFoundException: document $id introuvable';
}

/// Exception levée lors d'un échec inattendu de l'upload.
class DocumentUploadException implements Exception {
  const DocumentUploadException(this.message);

  final String message;

  @override
  String toString() => 'DocumentUploadException: $message';
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider exposant le repository documents.
final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return const SupabaseDocumentsRepository();
});

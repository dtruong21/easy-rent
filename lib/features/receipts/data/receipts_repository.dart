import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/firestore_helpers.dart';
import '../domain/document_type.dart';
import '../domain/receipt.dart';
import '../domain/receipt_generation_result.dart';
import 'receipt_pdf_renderer.dart';

final _log = Logger('ReceiptsRepository');

abstract interface class ReceiptsRepository {
  Future<List<Receipt>> listForLease(String leaseId);

  Future<Receipt> getById(String id);

  /// Génère une quittance via la Callable `generateReceipt` (FEAT-019).
  ///
  /// Le PDF n'est PLUS stocké côté serveur — la CF écrit seulement le doc
  /// Firestore avec snapshot complet immuable (preuve légale). Le PDF est
  /// rendu côté client via [renderPdfBytes] / [signedUrl].
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  });

  /// Rend le PDF d'une quittance côté client à partir des denorms Firestore.
  ///
  /// Retourne les bytes du PDF — caller utilise `Printing.layoutPdf`,
  /// `Printing.sharePdf`, ou convertit en data URL pour `launchUrl`.
  Future<Uint8List> renderPdfBytes(String receiptId);

  /// Compat layer — accepte le `pdfPath` historique (ignoré) OU directement
  /// le `receiptId`, rend le PDF et retourne une data URL `data:application/pdf;base64,...`
  /// utilisable avec `launchUrl()` et `webShare.fetchBytes()`.
  Future<String> signedUrl(String pdfPathOrReceiptId);

  /// Annule une quittance via la Callable `voidReceipt`.
  Future<void> voidReceipt(String id, String reason);

  /// Marque la quittance comme envoyée via la Callable `markReceiptAsSent`.
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  });
}

class FirestoreReceiptsRepository implements ReceiptsRepository {
  FirestoreReceiptsRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — receipt operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('receipts');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
  );

  @override
  Future<List<Receipt>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .orderBy('periodStart', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) =>
              Receipt.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Future<Receipt> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw ReceiptNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw ReceiptNotFoundException(id);
    }
    return Receipt.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    _log.info('generate(paymentIds=$paymentIds, leaseId=$leaseId)');
    try {
      final res = await _callable('generateReceipt').call(<String, dynamic>{
        'paymentIds': ?paymentIds,
        'leaseId': ?leaseId,
        'periodStart': ?periodStart?.toUtc().toIso8601String(),
        'periodEnd': ?periodEnd?.toUtc().toIso8601String(),
      });
      final data = (res.data as Map?) ?? const {};
      final receiptId = data['receiptId'] as String?;
      if (receiptId == null) {
        throw const ReceiptGenerationException(
          'generateReceipt did not return a receiptId',
        );
      }

      // Rendre l'URL signée (data URL avec bytes embedded) immédiatement
      // après création, pour ouverture/téléchargement par le caller.
      final pdfUrl = await signedUrl(receiptId);

      // Period bounds + total : on les retourne depuis la CF si possible,
      // sinon on re-lit le doc.
      final totalCents = (data['totalCents'] as int?) ?? 0;
      final documentTypeStr = (data['documentType'] as String?) ?? 'quittance';

      // Recharge le doc pour avoir les periodStart/End précis (utilisé par
      // les widgets de confirmation).
      final receipt = await getById(receiptId);

      return ReceiptGenerationResult(
        receiptId: receiptId,
        pdfUrl: pdfUrl,
        documentType: DocumentType.fromSql(documentTypeStr),
        totalCents: totalCents,
        periodStart: receipt.periodStart,
        periodEnd: receipt.periodEnd,
      );
    } on FirebaseFunctionsException catch (e) {
      final code = e.code;
      final msg = e.message ?? '';
      final details = e.details;
      if (msg.contains('profile_incomplete') ||
          (details is Map && details['missing'] != null)) {
        final missing = details is Map
            ? List<String>.from(
                (details['missing'] as List?) ?? const <String>[],
              )
            : <String>[];
        throw ProfileIncompleteException(missing: missing);
      }
      throw ReceiptGenerationException(
        'Erreur lors de la generation (code=$code): $msg',
      );
    }
  }

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async {
    _log.info('renderPdfBytes($receiptId)');
    final snap = await _col.doc(receiptId).get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw ReceiptNotFoundException(receiptId);
    }
    if (data['landlordId'] != _uid) {
      throw ReceiptNotFoundException(receiptId);
    }

    final pdfData = ReceiptPdfData(
      receiptId: snap.id,
      documentType: DocumentType.fromSql(
        (data['documentType'] as String?) ?? 'quittance',
      ),
      landlordFullName: (data['landlordFullName'] as String?) ?? '',
      landlordAddress: (data['landlordAddress'] as String?) ?? '',
      tenantFullName: (data['tenantFullName'] as String?) ?? '',
      propertyAddress: (data['propertyAddress'] as String?) ?? '',
      periodStart: _ts(data['periodStart']),
      periodEnd: _ts(data['periodEnd']),
      rentCents: (data['rentCents'] as int?) ?? 0,
      chargesCents: (data['chargesCents'] as int?) ?? 0,
      totalCents: (data['totalCents'] as int?) ?? 0,
      lastPaidAt: _ts(data['lastPaidAt']),
      generatedAt: _ts(data['generatedAt']),
    );
    return renderReceiptPdf(pdfData);
  }

  @override
  Future<String> signedUrl(String pdfPathOrReceiptId) async {
    _log.info('signedUrl($pdfPathOrReceiptId)');
    // Extrait l'id : si c'est un legacy path "receipts/{uid}/{id}.pdf" on
    // récupère la dernière partie sans extension, sinon on prend tel quel.
    final raw = pdfPathOrReceiptId;
    final id = raw.contains('/')
        ? raw.split('/').last.replaceAll('.pdf', '')
        : raw;
    final bytes = await renderPdfBytes(id);
    // Data URL embeds the PDF in-line. launchUrl + Web Share API les supportent.
    final base64 = base64Encode(bytes);
    return 'data:application/pdf;base64,$base64';
  }

  @override
  Future<void> voidReceipt(String id, String reason) async {
    _log.info('voidReceipt(id=$id)');
    await _callable(
      'voidReceipt',
    ).call(<String, dynamic>{'receiptId': id, 'reason': reason});
  }

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async {
    _log.info('markReceiptAsShared(receiptId=$receiptId)');
    await _callable(
      'markReceiptAsSent',
    ).call(<String, dynamic>{'receiptId': receiptId, 'email': tenantEmail});
    return getById(receiptId);
  }

  static DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class ReceiptNotFoundException implements Exception {
  const ReceiptNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'ReceiptNotFoundException: quittance $id introuvable';
}

class ReceiptGenerationException implements Exception {
  const ReceiptGenerationException(this.message);
  final String message;
  @override
  String toString() => 'ReceiptGenerationException: $message';
}

/// Levée par [generate] quand le profil bailleur n'a pas les champs requis
/// pour une quittance légale (fullName, address).
class ProfileIncompleteException implements Exception {
  const ProfileIncompleteException({required this.missing});
  final List<String> missing;
  @override
  String toString() =>
      'ProfileIncompleteException: champs manquants : ${missing.join(", ")}';
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return FirestoreReceiptsRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'web_share_service_interface.dart';

/// Implémentation Web de [WebShareService] utilisant la Web Share API.
///
/// Utilise `package:web` + `dart:js_interop` (APIs officielles Dart 3+).
/// Ne dépend PAS de `share_plus` — instable sur Web pour les fichiers.
///
/// Support navigateur :
/// - Chrome/Edge (desktop + Android) : oui, avec fichiers.
/// - Safari iOS 15+ : oui, avec fichiers.
/// - Firefox / Safari Desktop : non (Web Share API absente ou sans fichiers).
class WebShareServiceImpl implements WebShareService {
  const WebShareServiceImpl();

  @override
  bool canShareFiles() {
    if (!_hasCanShare()) return false;
    try {
      final dummyFile = web.File(
        [
          Uint8List.fromList([0]).toJS,
        ].toJS,
        'test.pdf',
        web.FilePropertyBag(type: 'application/pdf'),
      );
      final shareData = web.ShareData(files: [dummyFile].toJS);
      return web.window.navigator.canShare(shareData);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    if (!_hasCanShare()) {
      throw const ShareNotSupportedException();
    }

    final file = web.File(
      [Uint8List.fromList(pdfBytes).toJS].toJS,
      filename,
      web.FilePropertyBag(type: 'application/pdf'),
    );

    final shareData = web.ShareData(
      files: [file].toJS,
      title: title,
      text: text,
    );

    try {
      await web.window.navigator.share(shareData).toDart;
    } catch (e) {
      final js = e as JSAny?;
      if (js != null && js.isA<web.DOMException>()) {
        final dom = js as web.DOMException;
        if (dom.name == 'AbortError') throw const ShareAbortedException();
        throw ShareReceiptException(dom.message);
      }
      throw ShareReceiptException(e.toString());
    }
  }

  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async {
    try {
      final blob = web.Blob(
        [Uint8List.fromList(pdfBytes).toJS].toJS,
        web.BlobPropertyBag(type: 'application/pdf'),
      );
      final url = web.URL.createObjectURL(blob);
      web.window.open(url, '_blank');
      // Révocation DIFFÉRÉE, jamais immédiate : l'onglet lit l'URL de façon
      // asynchrone après son ouverture. Révoquer dans la foulée lui couperait
      // la source et redonnerait la page blanche qu'on corrige ici.
      Future<void>.delayed(
        const Duration(minutes: 2),
        () => web.URL.revokeObjectURL(url),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copyToClipboard(String text) async {
    try {
      await web.window.navigator.clipboard.writeText(text).toDart;
      return true;
    } catch (_) {
      // Le clipboard peut échouer en contexte non sécurisé ou permission refusée.
      return false;
    }
  }

  @override
  Future<List<int>> fetchBytes(String url) async {
    try {
      final response = await web.window.fetch(url.toJS).toDart;
      if (!response.ok) {
        throw ShareReceiptException(
          'HTTP ${response.status} lors du téléchargement du PDF',
        );
      }
      final buffer = await response.arrayBuffer().toDart;
      // JSArrayBuffer.toDart retourne un ByteBuffer Dart.
      // asUint8List() donne une vue Uint8List directement exploitable.
      return buffer.toDart.asUint8List();
    } on ShareReceiptException {
      rethrow;
    } catch (e) {
      throw ShareReceiptException('Téléchargement PDF échoué : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  /// Vérifie que `navigator.canShare()` existe sans lever d'exception.
  bool _hasCanShare() {
    try {
      // canShare() sans argument retourne true si l'API est disponible.
      web.window.navigator.canShare();
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider du service de partage Web Share API.
///
/// Sur les tests unitaires (VM), ce provider doit être overridé avec un mock.
final webShareServiceProvider = Provider<WebShareService>(
  (_) => const WebShareServiceImpl(),
);

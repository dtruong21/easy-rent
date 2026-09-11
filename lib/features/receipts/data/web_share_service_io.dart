import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'web_share_service_interface.dart';

/// Implémentation VM de [WebShareService] (FEAT-024).
///
/// - **Android / iOS** : partage natif via `share_plus` (share sheet
///   système, PDF en pièce jointe) — l'équivalent mobile de la Web Share
///   API. Choisi plutôt que `printing.sharePdf` car share_plus remonte
///   l'annulation du share sheet ([ShareResultStatus.dismissed]) sur les
///   deux plateformes, là où printing résout `true` dès l'ouverture —
///   indispensable pour l'invariant « marquage `sent_at` APRÈS partage
///   réussi » des quittances.
/// - **Autres plateformes VM** (tests unitaires, desktop) : no-op sûr —
///   `canShareFiles()` retourne `false`, les contrôleurs prennent leur
///   branche fallback. Les tests overrident [webShareServiceProvider] avec
///   un mock, comme avant.
class WebShareServiceImpl implements WebShareService {
  const WebShareServiceImpl();

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool canShareFiles() => _isMobile;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    if (!_isMobile) {
      throw const ShareNotSupportedException();
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(pdfBytes),
            mimeType: 'application/pdf',
          ),
        ],
        fileNameOverrides: [filename],
        subject: title,
        text: text,
        // iPad : le share sheet est un popover qui exige une ancre, sinon
        // crash UIKit. Ancre neutre en attendant un vrai anchoring (iPad
        // hors cible V1) ; ignoré sur iPhone/Android.
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
    // Même sémantique que l'AbortError web : pas de marquage `sent_at` si
    // l'utilisateur referme le share sheet sans choisir de cible.
    // `unavailable` (cible choisie mais résultat indéterminable) est traité
    // comme un succès, comme sur le web où seul l'abandon est signalé.
    if (result.status == ShareResultStatus.dismissed) {
      throw const ShareAbortedException();
    }
  }

  /// Best-effort, comme l'impl web : ne doit jamais faire échouer le flux
  /// de partage appelant.
  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async {
    // Hors Web, `launchUrl` sur une URL `data:` fonctionne (la restriction de
    // navigation de premier niveau est propre aux navigateurs). On renvoie
    // `false` pour laisser l'appelant conserver son chemin historique, plutôt
    // que d'introduire ici une écriture de fichier temporaire dont personne
    // n'a besoin aujourd'hui.
    return false;
  }

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {
    if (!_isMobile) return; // desktop / tests : no-op sûr
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mimeType)],
        fileNameOverrides: [filename],
        subject: shareTitle,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  }

  @override
  Future<bool> copyToClipboard(String text) async {
    if (!_isMobile) {
      return false;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Les PDF quittances sont rendus côté client : l'« URL signée » du repo
  /// receipts est une data-URL `data:application/pdf;base64,…` — décodage
  /// local, aucun appel réseau.
  @override
  Future<List<int>> fetchBytes(String url) async {
    final data = Uri.parse(url).data;
    if (data == null) {
      throw const ShareReceiptException(
        'fetchBytes hors data-URL non supporté sur cette plateforme',
      );
    }
    return data.contentAsBytes();
  }
}

/// Provider du service de partage (impl VM — overridé dans les tests).
final webShareServiceProvider = Provider<WebShareService>(
  (_) => const WebShareServiceImpl(),
);

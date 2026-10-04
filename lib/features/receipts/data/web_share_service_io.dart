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
        title: title,
        subject: title,
        // iOS : un texte joint au PDF devient un 2ᵉ élément de partage
        // (« Plain Text and 1 Document ») — « Enregistrer dans Fichiers »
        // créait un fichier texte parasite à côté du PDF, et la feuille de
        // partage perdait le titre et l'aperçu du PDF (recette iOS 27,
        // #197). On ne partage donc que le PDF, avec son titre et son sujet
        // d'email. Android garde le texte : il y part en corps de message
        // (EXTRA_TEXT), sans fichier en plus.
        text: Platform.isIOS ? null : text,
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
    // Desktop / tests : l'appelant garde son repli `launchUrl` (URL `data:`).
    if (!_isMobile) return false;
    // Mobile : le repli `data:` ne marche PAS — sur iOS `launchUrl` d'une URL
    // `data:` n'ouvre rien et ne rend jamais la main (recette simulateur
    // 2026-09-28 : quittance et état des lieux impossibles à consulter). On
    // présente le PDF dans la feuille de partage système : aperçu natif
    // (Quick Look sur iOS), « Enregistrer dans Fichiers », Mail, impression.
    // Une fermeture sans cible reste un succès : le document a été présenté.
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(pdfBytes),
            mimeType: 'application/pdf',
          ),
        ],
        fileNameOverrides: [filename],
        // Ancre iPad, cf. [sharePdf].
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
    return true;
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
        title: shareTitle,
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

/// Contrat du service de partage de fichiers PDF via Web Share API.
///
/// Deux implémentations :
/// - [WebShareServiceImpl] dans `web_share_service.dart` : utilise
///   `navigator.share()` (Web uniquement, `dart:js_interop`).
/// - [WebShareServiceImpl] dans `web_share_service_stub.dart` : stub no-op
///   pour les plateformes VM (tests unitaires).
abstract interface class WebShareService {
  /// `true` si le navigateur supporte `navigator.share()` avec des fichiers.
  ///
  /// Teste avec un fichier factice (1 byte) via `navigator.canShare()`.
  /// Sur Firefox et Safari Desktop, retourne `false`.
  bool canShareFiles();

  /// Partage un PDF via la Web Share API.
  ///
  /// Lance [ShareAbortedException] si l'utilisateur annule le dialog natif.
  /// Lance [ShareNotSupportedException] si l'API n'est pas disponible.
  /// Lance [ShareReceiptException] pour les autres erreurs.
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  });

  /// Copie [text] dans le presse-papier système.
  ///
  /// Retourne `true` si la copie a réussi, `false` sinon
  /// (permission refusée, contexte non sécurisé, etc.).
  Future<bool> copyToClipboard(String text);

  /// Télécharge les bytes d'une URL (GET) et les retourne.
  ///
  /// Utilisé pour récupérer le PDF depuis une URL signée Supabase Storage.
  /// Lance [ShareReceiptException] en cas d'échec réseau ou HTTP != 200.
  Future<List<int>> fetchBytes(String url);
}

/// Exception levée si l'utilisateur annule le dialog natif (AbortError JS).
class ShareAbortedException implements Exception {
  const ShareAbortedException();

  @override
  String toString() =>
      'ShareAbortedException: partage annulé par l\'utilisateur';
}

/// Exception levée si la Web Share API n'est pas disponible sur ce navigateur.
class ShareNotSupportedException implements Exception {
  const ShareNotSupportedException();

  @override
  String toString() =>
      'ShareNotSupportedException: Web Share API non disponible';
}

/// Exception générique lors du partage (DOMException autre qu'AbortError).
class ShareReceiptException implements Exception {
  const ShareReceiptException(this.message);

  final String message;

  @override
  String toString() => 'ShareReceiptException: $message';
}

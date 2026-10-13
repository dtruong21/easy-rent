/// Contrat du service de partage de fichiers PDF.
///
/// Deux implémentations (sélection par le bridge, FEAT-024) :
/// - [WebShareServiceImpl] dans `web_share_service.dart` : Web Share API
///   `navigator.share()` (Web uniquement, `dart:js_interop`).
/// - [WebShareServiceImpl] dans `web_share_service_io.dart` : share sheet
///   natif Android/iOS via `share_plus` ; no-op sûr sur les autres
///   plateformes VM (tests unitaires, desktop).
abstract interface class WebShareService {
  /// `true` si la plateforme sait partager un fichier nativement.
  ///
  /// Web : teste avec un fichier factice (1 byte) via `navigator.canShare()`
  /// — Firefox et Safari Desktop retournent `false`. VM : `true` sur
  /// Android/iOS, `false` ailleurs.
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
  /// Utilisé pour récupérer le PDF depuis une URL signée Firebase Storage.
  /// Lance [ShareReceiptException] en cas d'échec réseau ou HTTP != 200.
  Future<List<int>> fetchBytes(String url);

  /// Ouvre un PDF en mémoire dans la visionneuse du navigateur / de l'OS.
  ///
  /// Retourne `false` si la plateforme n'a pas su l'ouvrir — l'appelant
  /// affiche alors son message d'erreur habituel.
  ///
  /// **Pourquoi cette méthode existe.** Le chemin d'origine passait par une
  /// URL `data:application/pdf;base64,…` confiée à `launchUrl`. Or les
  /// navigateurs **bloquent la navigation de premier niveau vers une URL
  /// `data:`** (protection anti-hameçonnage, Chrome depuis la v60) : l'onglet
  /// s'ouvrait et restait BLANC. Signalé en recette sur staging le 2026-08-11,
  /// sur une quittance — donc un document à valeur légale, illisible.
  ///
  /// Le Web passe donc par une URL `blob:`, que les navigateurs acceptent en
  /// navigation et rendent dans leur visionneuse PDF intégrée. Les URLs `data:`
  /// ont en prime une limite de taille (~2 Mo sur Chrome) qu'une quittance avec
  /// logo peut approcher.
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  });

  /// Remet [bytes] à l'utilisateur sous forme de fichier nommé [filename].
  ///
  /// Web : déclenche un téléchargement (blob). Mobile (Android/iOS) : ouvre le
  /// share sheet natif. Autres plateformes VM (desktop, tests) : no-op sûr.
  /// Générique (tout [mimeType]) — utilisé par l'export RGPD (JSON).
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  });
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_share_service_interface.dart';

/// Stub no-op de [WebShareService] pour les plateformes VM (tests unitaires).
///
/// Toutes les méthodes retournent des valeurs par défaut sûres.
/// Les tests doivent overrider [webShareServiceProvider] avec un mock.
class WebShareServiceImpl implements WebShareService {
  const WebShareServiceImpl();

  @override
  bool canShareFiles() => false;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {}

  @override
  Future<bool> copyToClipboard(String text) async => false;

  @override
  Future<List<int>> fetchBytes(String url) async => [];
}

/// Provider du service de partage (stub VM — overridé dans les tests).
final webShareServiceProvider = Provider<WebShareService>(
  (_) => const WebShareServiceImpl(),
);

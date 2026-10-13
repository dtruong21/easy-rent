/// Tests basiques de [WebShareService] via un mock.
///
/// Couvre :
/// - ShareAbortedException propagée
/// - ShareNotSupportedException propagée
/// - ShareReceiptException propagée
/// - canShareFiles retourne la valeur configurée
/// - copyToClipboard retourne la valeur configurée
/// - fetchBytes retourne les bytes configurés ou propage l'exception
library;

import 'package:easyrent/features/receipts/data/web_share_service_interface.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class _MockWebShareService implements WebShareService {
  bool _canShare = false;
  Exception? _shareException;
  bool _clipboardResult = true;
  Exception? _clipboardException;
  List<int>? _fetchResult;
  Exception? _fetchException;

  void setCanShare(bool value) => _canShare = value;

  void simulateShareException(Exception e) => _shareException = e;

  void setClipboardResult(bool value) => _clipboardResult = value;

  void simulateClipboardException(Exception e) => _clipboardException = e;

  void setFetchResult(List<int> bytes) => _fetchResult = bytes;

  void simulateFetchException(Exception e) => _fetchException = e;

  @override
  bool canShareFiles() => _canShare;

  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async => false;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    if (_shareException != null) throw _shareException!;
  }

  @override
  Future<bool> copyToClipboard(String text) async {
    if (_clipboardException != null) throw _clipboardException!;
    return _clipboardResult;
  }

  @override
  Future<List<int>> fetchBytes(String url) async {
    if (_fetchException != null) throw _fetchException!;
    return _fetchResult ?? [];
  }

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockWebShareService service;

  setUp(() => service = _MockWebShareService());

  group('canShareFiles', () {
    test('retourne false par défaut', () {
      expect(service.canShareFiles(), false);
    });

    test('retourne true si configuré', () {
      service.setCanShare(true);
      expect(service.canShareFiles(), true);
    });
  });

  group('sharePdf — exceptions propagées', () {
    test('propage ShareAbortedException', () {
      service.simulateShareException(const ShareAbortedException());
      expect(
        () => service.sharePdf(
          title: 'test',
          text: 'body',
          pdfBytes: [],
          filename: 'test.pdf',
        ),
        throwsA(isA<ShareAbortedException>()),
      );
    });

    test('propage ShareNotSupportedException', () {
      service.simulateShareException(const ShareNotSupportedException());
      expect(
        () => service.sharePdf(
          title: 'test',
          text: 'body',
          pdfBytes: [],
          filename: 'test.pdf',
        ),
        throwsA(isA<ShareNotSupportedException>()),
      );
    });

    test('propage ShareReceiptException', () {
      service.simulateShareException(const ShareReceiptException('DOM error'));
      expect(
        () => service.sharePdf(
          title: 'test',
          text: 'body',
          pdfBytes: [],
          filename: 'test.pdf',
        ),
        throwsA(isA<ShareReceiptException>()),
      );
    });

    test('sharePdf réussit sans exception', () async {
      await expectLater(
        service.sharePdf(
          title: 'test',
          text: 'body',
          pdfBytes: [1, 2, 3],
          filename: 'test.pdf',
        ),
        completes,
      );
    });
  });

  group('copyToClipboard', () {
    test('retourne true par défaut', () async {
      final result = await service.copyToClipboard('test@example.com');
      expect(result, true);
    });

    test('retourne false si configuré', () async {
      service.setClipboardResult(false);
      final result = await service.copyToClipboard('test@example.com');
      expect(result, false);
    });
  });

  group('fetchBytes', () {
    test('retourne les bytes configurés', () async {
      service.setFetchResult([1, 2, 3, 4]);
      final bytes = await service.fetchBytes('https://example.com/test.pdf');
      expect(bytes, [1, 2, 3, 4]);
    });

    test('propage ShareReceiptException', () {
      service.simulateFetchException(
        const ShareReceiptException('HTTP 404 lors du téléchargement'),
      );
      expect(
        () => service.fetchBytes('https://example.com/missing.pdf'),
        throwsA(isA<ShareReceiptException>()),
      );
    });
  });

  group('exceptions — toString', () {
    test('ShareAbortedException.toString non vide', () {
      const ex = ShareAbortedException();
      expect(ex.toString(), isNotEmpty);
    });

    test('ShareNotSupportedException.toString non vide', () {
      const ex = ShareNotSupportedException();
      expect(ex.toString(), isNotEmpty);
    });

    test('ShareReceiptException.toString contient le message', () {
      const ex = ShareReceiptException('erreur test');
      expect(ex.toString(), contains('erreur test'));
    });
  });
}

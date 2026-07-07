import 'dart:convert';

import 'package:easyrent/features/receipts/data/web_share_service_interface.dart';
import 'package:easyrent/features/receipts/data/web_share_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

// L'impl io tourne telle quelle en `flutter test` (VM desktop) : _isMobile
// est faux, donc aucune méthode ne touche de platform channel — on teste le
// contrat no-op + le décodage data-URL (pur Dart, déterministe).
void main() {
  const service = WebShareServiceImpl();

  group('WebShareServiceImpl (io) — contrat VM hors mobile', () {
    test('canShareFiles → false (branche fallback des contrôleurs)', () {
      expect(service.canShareFiles(), isFalse);
    });

    test('sharePdf → ShareNotSupportedException', () {
      expect(
        () => service.sharePdf(
          title: 'Quittance',
          text: 'corps',
          pdfBytes: [1, 2, 3],
          filename: 'quittance.pdf',
        ),
        throwsA(isA<ShareNotSupportedException>()),
      );
    });

    test(
      'copyToClipboard → false (best-effort, jamais d\'exception)',
      () async {
        expect(await service.copyToClipboard('jean@exemple.fr'), isFalse);
      },
    );
  });

  group('WebShareServiceImpl.fetchBytes (décodage data-URL)', () {
    test('data-URL base64 → bytes du PDF restitués', () async {
      final pdfBytes = [0x25, 0x50, 0x44, 0x46, 0x2D]; // '%PDF-'
      final url = 'data:application/pdf;base64,${base64Encode(pdfBytes)}';

      expect(await service.fetchBytes(url), pdfBytes);
    });

    test('URL non data (https) → ShareReceiptException', () {
      expect(
        () => service.fetchBytes('https://example.com/quittance.pdf'),
        throwsA(isA<ShareReceiptException>()),
      );
    });
  });
}

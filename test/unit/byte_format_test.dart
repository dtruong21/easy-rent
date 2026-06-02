/// Tests du helper [ByteFormat].
library;

import 'package:easyrent/core/utils/byte_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteFormat.format', () {
    test('0 octets → "0 o"', () {
      expect(ByteFormat.format(0), '0 o');
    });

    test('512 octets → "512 o"', () {
      expect(ByteFormat.format(512), '512 o');
    });

    test('1023 octets → "1023 o" (encore en octets)', () {
      expect(ByteFormat.format(1023), '1023 o');
    });

    test('1024 octets → "1 Ko"', () {
      expect(ByteFormat.format(1024), '1 Ko');
    });

    test('870400 → environ "850 Ko"', () {
      final result = ByteFormat.format(870400);
      expect(result, contains('Ko'));
    });

    test('1048575 → encore en Ko (juste en dessous de 1 Mo)', () {
      final result = ByteFormat.format(1048575);
      expect(result, contains('Ko'));
    });

    test('1048576 octets → "1 Mo"', () {
      expect(ByteFormat.format(1048576), '1 Mo');
    });

    test('10485760 (10 Mo) → contient "Mo"', () {
      final result = ByteFormat.format(10485760);
      expect(result, contains('Mo'));
    });

    test('utilise la virgule FR comme séparateur décimal', () {
      // 1.5 Mo = 1572864 octets
      final result = ByteFormat.format(1572864);
      expect(result, contains(','));
      expect(result, contains('Mo'));
    });

    test('valeur en Ko n\'utilise pas de point décimal FR', () {
      // 2048 octets = 2 Ko exact
      final result = ByteFormat.format(2048);
      expect(result, '2 Ko');
    });
  });
}

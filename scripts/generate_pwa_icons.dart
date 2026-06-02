// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

/// Script Dart standalone pour générer les icônes PWA placeholder "ER".
///
/// Génère des PNG valides fond teal #0F766E (15, 118, 110) en Dart pur.
/// Exécution : dart run scripts/generate_pwa_icons.dart
void main() {
  final iconsDir = Directory('web/icons');
  if (!iconsDir.existsSync()) {
    iconsDir.createSync(recursive: true);
  }

  final icons = [
    (192, 'Icon-192.png'),
    (512, 'Icon-512.png'),
    (192, 'Icon-maskable-192.png'),
    (512, 'Icon-maskable-512.png'),
  ];

  for (final (size, filename) in icons) {
    final path = 'web/icons/$filename';
    final bytes = _createPng(size, size);
    File(path).writeAsBytesSync(bytes);
    print('  Generated $path (${bytes.length} bytes)');
  }

  print('Done. Icons written to web/icons/');
}

/// Crée un PNG [w]×[h] avec fond teal #0F766E (RGB 15, 118, 110).
///
/// Implémentation RFC 2083 en Dart pur — sans dépendance externe.
Uint8List _createPng(int w, int h) {
  // Signature PNG
  final sig = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR : largeur, hauteur, bit depth=8, color type=2 (RGB), compression, filter, interlace
  final ihdr = _pngChunk(
    'IHDR',
    Uint8List.fromList([
      ..._pack32(w),
      ..._pack32(h),
      8, 2, 0, 0, 0,
    ]),
  );

  // Pixels : fond teal #0F766E = RGB (15, 118, 110)
  const r = 15, g = 118, b = 110;
  final scanlines = BytesBuilder();
  for (int y = 0; y < h; y++) {
    scanlines.addByte(0); // filter type None
    for (int x = 0; x < w; x++) {
      scanlines.addByte(r);
      scanlines.addByte(g);
      scanlines.addByte(b);
    }
  }
  final rawPixels = scanlines.toBytes();
  final compressed = _zlibCompress(rawPixels);
  final idat = _pngChunk('IDAT', compressed);

  // IEND
  final iend = _pngChunk('IEND', Uint8List(0));

  final result = BytesBuilder()
    ..add(sig)
    ..add(ihdr)
    ..add(idat)
    ..add(iend);
  return result.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final crcInput = Uint8List(typeBytes.length + data.length)
    ..setAll(0, typeBytes)
    ..setAll(typeBytes.length, data);
  final crc = _crc32(crcInput);
  final result = BytesBuilder()
    ..add(_pack32(data.length))
    ..add(typeBytes)
    ..add(data)
    ..add(_pack32(crc));
  return result.toBytes();
}

List<int> _pack32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

/// Compression zlib avec blocs DEFLATE non compressés (BTYPE=00).
///
/// Non compressé mais valide — acceptable pour de petits fichiers.
Uint8List _zlibCompress(Uint8List data) {
  final result = BytesBuilder();
  // CMF + FLG : 0x78 0x01 (deflate, no dict, FCHECK correct : 0x7801 % 31 == 0)
  result.addByte(0x78);
  result.addByte(0x01);

  int offset = 0;
  while (offset < data.length) {
    final remaining = data.length - offset;
    final blockSize = remaining < 65535 ? remaining : 65535;
    final isLast = (offset + blockSize) >= data.length;

    result.addByte(isLast ? 0x01 : 0x00); // BFINAL | BTYPE=00
    result.addByte(blockSize & 0xff);
    result.addByte((blockSize >> 8) & 0xff);
    result.addByte((~blockSize) & 0xff);
    result.addByte(((~blockSize) >> 8) & 0xff);
    result.add(data.sublist(offset, offset + blockSize));
    offset += blockSize;
  }

  // Adler-32 checksum (big-endian)
  int s1 = 1, s2 = 0;
  for (final b in data) {
    s1 = (s1 + b) % 65521;
    s2 = (s2 + s1) % 65521;
  }
  result.add(_pack32((s2 << 16) | s1));
  return result.toBytes();
}

int _crc32(Uint8List data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

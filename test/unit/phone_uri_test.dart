import 'package:easyrent/core/utils/phone_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smsUri : schéma sms, numéro nettoyé, body en query', () {
    final u = smsUri(phone: '06 12 34 56 78', body: 'Bonjour');
    expect(u.scheme, 'sms');
    expect(u.path, '0612345678');
    expect(u.queryParameters['body'], 'Bonjour');
  });

  test('whatsAppUri : 06… → 336…', () {
    final u = whatsAppUri(phone: '06 12 34 56 78', text: 'Bonjour');
    expect(u, isNotNull);
    expect(u!.host, 'wa.me');
    expect(u.path, '/33612345678');
    expect(u.queryParameters['text'], 'Bonjour');
  });

  test('whatsAppUri : +33 6… et 0033 6… → 336…', () {
    expect(
      whatsAppUri(phone: '+33 6 12 34 56 78', text: 'x')!.path,
      '/33612345678',
    );
    expect(
      whatsAppUri(phone: '0033612345678', text: 'x')!.path,
      '/33612345678',
    );
  });

  test('whatsAppUri : numéro non-FR / invalide → null', () {
    expect(whatsAppUri(phone: '+1 202 555 0100', text: 'x'), isNull);
    expect(whatsAppUri(phone: 'pas un numéro', text: 'x'), isNull);
  });
}

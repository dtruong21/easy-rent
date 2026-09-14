/// Construction d'URI de messagerie à partir d'un numéro de téléphone
/// (FEAT-031 — relance assistée). V1 : normalisation WhatsApp limitée aux
/// numéros français.
library;

/// Ne garde que les chiffres d'une chaîne (retire espaces, points, tirets, +).
String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// URI `sms:` pré-remplie. Le numéro est nettoyé de ses séparateurs mais
/// conservé tel quel sinon (les apps SMS acceptent le format local).
Uri smsUri({required String phone, required String body}) {
  return Uri(
    scheme: 'sms',
    path: _digitsOnly(phone),
    queryParameters: {'body': body},
  );
}

/// URI `https://wa.me/<E164 sans +>?text=…` pour un numéro **français**.
///
/// Normalise `06XXXXXXXX`, `+336XXXXXXXX`, `00336XXXXXXXX` → `336XXXXXXXX`.
/// Retourne `null` si le numéro n'est pas un mobile/fixe FR reconnaissable
/// (l'appelant masque alors l'option WhatsApp). V1 FR-only assumé.
Uri? whatsAppUri({required String phone, required String text}) {
  var d = _digitsOnly(phone);
  // 0033… → 33…
  if (d.startsWith('0033')) d = d.substring(2);
  // 33XXXXXXXXX déjà au bon format (11 chiffres : 33 + 9)
  if (d.startsWith('33') && d.length == 11) {
    return Uri.parse('https://wa.me/$d?text=${Uri.encodeQueryComponent(text)}');
  }
  // 0XXXXXXXXX (10 chiffres, national FR) → 33 + les 9 chiffres après le 0
  if (d.startsWith('0') && d.length == 10) {
    return Uri.parse(
      'https://wa.me/33${d.substring(1)}?text=${Uri.encodeQueryComponent(text)}',
    );
  }
  return null;
}

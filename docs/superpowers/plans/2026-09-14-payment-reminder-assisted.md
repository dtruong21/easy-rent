# FEAT-031 V1 — Relance de paiement assistée — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter sur la fiche bail un bouton « Relancer le locataire » (visible si le bail est en retard) qui ouvre l'app email/SMS/WhatsApp du bailleur avec un message de relance amiable pré-rempli — 100 % côté client, zéro backend.

**Architecture:** Trois briques pures et testables (mois dû courant exposé depuis la logique de retard FEAT-028 ; constructeur de message ; constructeur d'URI de canal + normalisation téléphone), puis un widget qui sélectionne le canal disponible et appelle `launchUrl`. Réutilise le patron `mailto:`/`launchUrl` déjà en production pour le partage des quittances (`share_receipt_controller.dart`). Aucune écriture Firestore, aucun callable, aucun secret.

**Tech Stack:** Flutter/Dart, `url_launcher` (déjà présent), i18n `.arb` FR/EN + `flutter gen-l10n`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-14-payment-reminder-assisted-design.md`

## Global Constraints

- **100 % client** : aucune écriture Firestore, aucun callable, aucun secret, aucune dépendance nouvelle (url_launcher déjà là). Ne rien déployer côté backend.
- **Montants** : entiers centimes ; affichage `MoneyFormat.formatEurosFromCents` (format `1 234,56 €`, espace insécable).
- **Dates/mois** : mois en français via `FrenchDate.frenchMonthYear(DateTime)` → ex. `septembre 2026`.
- **Fuseau** : toute lecture `.year/.month/.day` d'une date bail passe par `leaseLocalDate` (déjà en place dans `lease_lateness.dart`) — ne pas ré-introduire le bug fuseau (#181).
- **Légal** : le corps du message DOIT contenir une mention explicite « relance amiable » et « ne constitue pas une mise en demeure ». La relance part de la messagerie/du numéro du bailleur (jamais « au nom de Baillan »).
- **i18n** : nouvelles clés dans `lib/l10n/app_fr.arb` ET `lib/l10n/app_en.arb`, `@description` sur le template EN ; parité imposée par `test/l10n/arb_parity_test.dart` ; régénérer via `flutter gen-l10n` (fichiers générés gitignorés — ne pas les committer).
- **Accès l10n** : `context.l10n.<clé>` (extension existante, cf. `lease_detail_page.dart`).
- **launchUrl** : `launchUrl(uri, mode: LaunchMode.externalApplication)` (import `package:url_launcher/url_launcher.dart`), comme `share_receipt_controller.dart`.
- **Format CI** : `dart format .` avant push (la CI lance `dart format --set-exit-if-changed .`).
- **PATH** : préfixer chaque commande shell par `export PATH="/opt/homebrew/bin:$PATH"`.

---

## File Structure

- Modify `lib/features/leases/domain/lease_lateness.dart` — exposer une fonction publique `leaseCurrentDueMonth(...)` (mois dû courant), réutilisant la logique privée existante.
- Create `lib/features/leases/domain/payment_reminder_message.dart` — constructeur pur du message (sujet + corps).
- Create `lib/core/utils/phone_uri.dart` — `smsUri`, `whatsAppUri` (normalisation FR).
- Create `lib/features/leases/domain/payment_reminder_channel.dart` — enum `ReminderChannel` + `reminderUriFor(...)` (mailto/sms/wa.me) + `availableReminderChannels(...)`.
- Create `lib/features/leases/presentation/widgets/payment_reminder_button.dart` — bouton + bottom sheet de sélection de canal, appelle `launchUrl`.
- Modify `lib/features/leases/presentation/lease_detail_page.dart` — monter le bouton après `_StatusCard` (si `isLate`) + fournir landlordFullName/propertyAddress/tenant.
- Modify `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb` — clés i18n.
- Tests : `test/unit/lease_current_due_month_test.dart`, `test/unit/payment_reminder_message_test.dart`, `test/unit/phone_uri_test.dart`, `test/unit/payment_reminder_channel_test.dart`, `test/widget/payment_reminder_button_test.dart`.
- Docs : `docs/state/routes/leases.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`.

---

## Task 1 — Exposer le « mois dû courant » (lease_lateness)

**Files:**
- Modify: `lib/features/leases/domain/lease_lateness.dart`
- Test: `test/unit/lease_current_due_month_test.dart`

**Interfaces:**
- Consumes : logique privée existante `_currentDueMonth`, `leaseLocalDate`, `kDefaultLeaseGraceDays` (même fichier).
- Produces : `DateTime? leaseCurrentDueMonth({required DateTime startDate, required int paymentDay, required DateTime now, int graceDays = kDefaultLeaseGraceDays})` — retourne le 1er jour (à midi local) du mois dû courant, ou `null` si aucun mois n'est encore dû.

Le fichier a déjà une fonction privée `_currentDueMonth(...)` renvoyant le typedef privé `_YearMonth? ({int year, int month})`. On expose un wrapper public qui renvoie un `DateTime?` (utilisable par `FrenchDate.frenchMonthYear`), sans exposer le typedef privé.

- [ ] **Step 1: Écrire le test (échouant)**

```dart
import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // paymentDay=5, grâce 5 j. Bail démarré le 01/01/2026.
  test('mois dû courant = mois précédent quand la deadline est passée', () {
    // now = 20 mars 2026 → l'échéance de mars (5 mars) + grâce (10 mars) est
    // passée → mois dû courant = mars 2026.
    final due = leaseCurrentDueMonth(
      startDate: DateTime(2026, 1, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 20),
    );
    expect(due, isNotNull);
    expect(due!.year, 2026);
    expect(due.month, 3);
  });

  test('null quand aucune échéance n\'est encore due (bail tout neuf)', () {
    final due = leaseCurrentDueMonth(
      startDate: DateTime(2026, 3, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 2), // avant échéance+grâce du 1er mois
    );
    expect(due, isNull);
  });

  test('invariance fuseau : une date UTC-round-trippée donne le même mois', () {
    DateTime rt(DateTime d) => DateTime.parse(d.toUtc().toIso8601String());
    final local = leaseCurrentDueMonth(
      startDate: DateTime(2026, 1, 1),
      paymentDay: 5,
      now: DateTime(2026, 3, 20),
    );
    final roundTripped = leaseCurrentDueMonth(
      startDate: rt(DateTime(2026, 1, 1)),
      paymentDay: 5,
      now: rt(DateTime(2026, 3, 20)),
    );
    expect(roundTripped!.month, local!.month);
    expect(roundTripped.year, local.year);
  });
}
```

- [ ] **Step 2: Lancer → échec** (`leaseCurrentDueMonth` non défini).

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/lease_current_due_month_test.dart`

- [ ] **Step 3: Implémenter le wrapper public**

Ajouter dans `lib/features/leases/domain/lease_lateness.dart` (après `isLeaseLate`, avant les helpers privés) :

```dart
/// Mois calendaire dont le loyer est actuellement dû et impayable-sans-retard
/// dépassé, pour un bail démarrant [startDate] avec échéance [paymentDay].
///
/// Wrapper public de [_currentDueMonth] renvoyant le 1er jour du mois (midi
/// local, pour éviter tout effet de bord de fuseau à l'affichage) — utilisable
/// directement avec `FrenchDate.frenchMonthYear`. `null` si aucun mois n'est
/// encore dû (bail trop récent / 1ʳᵉ échéance dans le délai de grâce).
DateTime? leaseCurrentDueMonth({
  required DateTime startDate,
  required int paymentDay,
  required DateTime now,
  int graceDays = kDefaultLeaseGraceDays,
}) {
  final ym = _currentDueMonth(
    startDate: leaseLocalDate(startDate),
    paymentDay: paymentDay,
    now: leaseLocalDate(now),
    graceDays: graceDays,
  );
  if (ym == null) return null;
  return DateTime(ym.year, ym.month, 1, 12);
}
```

- [ ] **Step 4: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/lease_current_due_month_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/leases/domain/lease_lateness.dart test/unit/lease_current_due_month_test.dart
git add lib/features/leases/domain/lease_lateness.dart test/unit/lease_current_due_month_test.dart
git commit -m "feat(leases): expose leaseCurrentDueMonth pour la relance (FEAT-031)"
```

---

## Task 2 — Constructeur de message de relance (pur)

**Files:**
- Create: `lib/features/leases/domain/payment_reminder_message.dart`
- Test: `test/unit/payment_reminder_message_test.dart`

**Interfaces:**
- Consumes : `MoneyFormat.formatEurosFromCents` (`lib/core/utils/money_format.dart`).
- Produces : classe `PaymentReminderMessage({required String subject, required String body})` ; `PaymentReminderMessage buildPaymentReminderMessage({required String tenantFirstName, required String landlordFullName, required String propertyAddress, required String dueMonthLabel, required int amountDueCents})`.

Les libellés sont en français **en dur ici** (le message part vers l'app native du bailleur ; le contenu métier/légal est identique quelle que soit la locale de l'UI — on ne le traduit pas via l10n pour garder la fonction pure et testable sans `BuildContext`). Les libellés d'UI (bouton, canaux, erreurs) sont eux dans les `.arb` (Task 5).

- [ ] **Step 1: Écrire le test (échouant)**

```dart
import 'package:easyrent/features/leases/domain/payment_reminder_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaymentReminderMessage build() => buildPaymentReminderMessage(
    tenantFirstName: 'Marie',
    landlordFullName: 'Jean Bailleur',
    propertyAddress: '2 rue de Lyon, 69001 Lyon',
    dueMonthLabel: 'septembre 2026',
    amountDueCents: 85000,
  );

  test('sujet mentionne la période', () {
    expect(build().subject, contains('septembre 2026'));
  });

  test('corps mentionne prénom, adresse, montant formaté et signature', () {
    final b = build().body;
    expect(b, contains('Marie'));
    expect(b, contains('2 rue de Lyon, 69001 Lyon'));
    expect(b, contains('850,00')); // MoneyFormat (espace insécable avant €)
    expect(b, contains('Jean Bailleur'));
  });

  test('corps contient la mention légale relance amiable / pas mise en demeure', () {
    final b = build().body.toLowerCase();
    expect(b, contains('relance amiable'));
    expect(b, contains('mise en demeure'));
  });
}
```

- [ ] **Step 2: Lancer → échec.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/payment_reminder_message_test.dart`

- [ ] **Step 3: Implémenter**

```dart
import '../../../core/utils/money_format.dart';

/// Message de relance de paiement pré-rempli (sujet + corps), destiné à être
/// ouvert dans l'app email/SMS/WhatsApp du bailleur (FEAT-031 V1). Contenu
/// métier en français, indépendant de la locale de l'UI.
class PaymentReminderMessage {
  const PaymentReminderMessage({required this.subject, required this.body});

  final String subject;
  final String body;
}

/// Construit le message de relance amiable. Fonction pure, testable.
///
/// Le corps porte OBLIGATOIREMENT la mention « relance amiable » + « ne
/// constitue pas une mise en demeure » (contrainte légale — une mise en
/// demeure exige un acte formel / LRAR, hors périmètre).
PaymentReminderMessage buildPaymentReminderMessage({
  required String tenantFirstName,
  required String landlordFullName,
  required String propertyAddress,
  required String dueMonthLabel,
  required int amountDueCents,
}) {
  final amount = MoneyFormat.formatEurosFromCents(amountDueCents);
  final subject = 'Rappel — loyer de $dueMonthLabel';
  final body =
      'Bonjour $tenantFirstName,\n\n'
      'Sauf erreur de ma part, le loyer de $dueMonthLabel pour le logement '
      'situé $propertyAddress, d\'un montant de $amount, ne m\'apparaît pas '
      'encore réglé.\n\n'
      'Je vous remercie de bien vouloir procéder à sa régularisation. Si le '
      'paiement a déjà été effectué, merci de ne pas tenir compte de ce '
      'message.\n\n'
      'Ceci est une relance amiable et ne constitue pas une mise en demeure.\n\n'
      'Cordialement,\n'
      '$landlordFullName\n\n'
      '---\n'
      'Émis via Baillan.';
  return PaymentReminderMessage(subject: subject, body: body);
}
```

- [ ] **Step 4: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/payment_reminder_message_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/leases/domain/payment_reminder_message.dart test/unit/payment_reminder_message_test.dart
git add lib/features/leases/domain/payment_reminder_message.dart test/unit/payment_reminder_message_test.dart
git commit -m "feat(leases): constructeur de message de relance amiable (FEAT-031)"
```

---

## Task 3 — Normalisation téléphone (SMS / WhatsApp)

**Files:**
- Create: `lib/core/utils/phone_uri.dart`
- Test: `test/unit/phone_uri_test.dart`

**Interfaces:**
- Produces : `Uri smsUri({required String phone, required String body})` ; `Uri? whatsAppUri({required String phone, required String text})` (`null` si le numéro n'est pas normalisable en FR).

- [ ] **Step 1: Écrire le test (échouant)**

```dart
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
    expect(whatsAppUri(phone: '+33 6 12 34 56 78', text: 'x')!.path, '/33612345678');
    expect(whatsAppUri(phone: '0033612345678', text: 'x')!.path, '/33612345678');
  });

  test('whatsAppUri : numéro non-FR / invalide → null', () {
    expect(whatsAppUri(phone: '+1 202 555 0100', text: 'x'), isNull);
    expect(whatsAppUri(phone: 'pas un numéro', text: 'x'), isNull);
  });
}
```

- [ ] **Step 2: Lancer → échec.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/phone_uri_test.dart`

- [ ] **Step 3: Implémenter**

```dart
/// Construction d'URI de messagerie à partir d'un numéro de téléphone
/// (FEAT-031 — relance assistée). V1 : normalisation WhatsApp limitée aux
/// numéros français.

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
```

> Note : pour `wa.me` on construit l'URL via `Uri.parse` + `Uri.encodeQueryComponent` (l'hôte `wa.me` et le path E.164 sont fixes). Pour `sms:` on utilise le constructeur `Uri(...)` qui encode `body`.

- [ ] **Step 4: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/phone_uri_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/core/utils/phone_uri.dart test/unit/phone_uri_test.dart
git add lib/core/utils/phone_uri.dart test/unit/phone_uri_test.dart
git commit -m "feat(core): phone_uri (sms + wa.me FR) pour la relance (FEAT-031)"
```

---

## Task 4 — Canaux de relance + constructeur d'URI (pur)

**Files:**
- Create: `lib/features/leases/domain/payment_reminder_channel.dart`
- Test: `test/unit/payment_reminder_channel_test.dart`

**Interfaces:**
- Consumes : `PaymentReminderMessage` (Task 2) ; `smsUri`, `whatsAppUri` (Task 3).
- Produces : `enum ReminderChannel { email, sms, whatsApp }` ; `List<ReminderChannel> availableReminderChannels({required String? phone})` ; `Uri? reminderUriFor({required ReminderChannel channel, required String tenantEmail, required String? tenantPhone, required PaymentReminderMessage message})`.

- [ ] **Step 1: Écrire le test (échouant)**

```dart
import 'package:easyrent/features/leases/domain/payment_reminder_channel.dart';
import 'package:easyrent/features/leases/domain/payment_reminder_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const msg = PaymentReminderMessage(subject: 'Rappel', body: 'Bonjour');

  test('email seul quand pas de téléphone', () {
    expect(availableReminderChannels(phone: null), [ReminderChannel.email]);
    expect(availableReminderChannels(phone: ''), [ReminderChannel.email]);
  });

  test('email + sms + whatsApp pour un mobile FR', () {
    expect(availableReminderChannels(phone: '06 12 34 56 78'),
        [ReminderChannel.email, ReminderChannel.sms, ReminderChannel.whatsApp]);
  });

  test('email + sms seulement pour un numéro non-FR (whatsApp indisponible)', () {
    expect(availableReminderChannels(phone: '+1 202 555 0100'),
        [ReminderChannel.email, ReminderChannel.sms]);
  });

  test('reminderUriFor email → mailto avec subject+body', () {
    final u = reminderUriFor(
      channel: ReminderChannel.email,
      tenantEmail: 'loc@ex.fr',
      tenantPhone: null,
      message: msg,
    );
    expect(u!.scheme, 'mailto');
    expect(u.path, 'loc@ex.fr');
    expect(u.queryParameters['subject'], 'Rappel');
    expect(u.queryParameters['body'], 'Bonjour');
  });

  test('reminderUriFor whatsApp sur numéro non-FR → null', () {
    final u = reminderUriFor(
      channel: ReminderChannel.whatsApp,
      tenantEmail: 'loc@ex.fr',
      tenantPhone: '+1 202 555 0100',
      message: msg,
    );
    expect(u, isNull);
  });
}
```

- [ ] **Step 2: Lancer → échec.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/payment_reminder_channel_test.dart`

- [ ] **Step 3: Implémenter**

```dart
import '../../../core/utils/phone_uri.dart';
import 'payment_reminder_message.dart';

/// Canaux de relance disponibles (FEAT-031 V1).
enum ReminderChannel { email, sms, whatsApp }

bool _hasPhone(String? phone) => phone != null && phone.trim().isNotEmpty;

/// Canaux proposables pour ce locataire : email toujours ; sms si téléphone ;
/// whatsApp seulement si le téléphone est normalisable en FR (cf.
/// [whatsAppUri]).
List<ReminderChannel> availableReminderChannels({required String? phone}) {
  final channels = <ReminderChannel>[ReminderChannel.email];
  if (_hasPhone(phone)) {
    channels.add(ReminderChannel.sms);
    if (whatsAppUri(phone: phone!, text: '') != null) {
      channels.add(ReminderChannel.whatsApp);
    }
  }
  return channels;
}

/// Construit l'URI à ouvrir pour [channel]. `null` si le canal n'est pas
/// exploitable (ex. whatsApp sur numéro non-FR, ou sms/whatsApp sans
/// téléphone) — l'appelant ne devrait proposer que des canaux issus de
/// [availableReminderChannels].
Uri? reminderUriFor({
  required ReminderChannel channel,
  required String tenantEmail,
  required String? tenantPhone,
  required PaymentReminderMessage message,
}) {
  switch (channel) {
    case ReminderChannel.email:
      return Uri(
        scheme: 'mailto',
        path: tenantEmail,
        queryParameters: {'subject': message.subject, 'body': message.body},
      );
    case ReminderChannel.sms:
      if (!_hasPhone(tenantPhone)) return null;
      return smsUri(phone: tenantPhone!, body: message.body);
    case ReminderChannel.whatsApp:
      if (!_hasPhone(tenantPhone)) return null;
      return whatsAppUri(phone: tenantPhone!, text: message.body);
  }
}
```

- [ ] **Step 4: Lancer → succès.**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter test test/unit/payment_reminder_channel_test.dart`

- [ ] **Step 5: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/leases/domain/payment_reminder_channel.dart test/unit/payment_reminder_channel_test.dart
git add lib/features/leases/domain/payment_reminder_channel.dart test/unit/payment_reminder_channel_test.dart
git commit -m "feat(leases): canaux de relance + reminderUriFor (FEAT-031)"
```

---

## Task 5 — Bouton « Relancer le locataire » + montage fiche bail + i18n

**Files:**
- Create: `lib/features/leases/presentation/widgets/payment_reminder_button.dart`
- Modify: `lib/features/leases/presentation/lease_detail_page.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/payment_reminder_button_test.dart`

**Interfaces:**
- Consumes : `leaseCurrentDueMonth` (Task 1) ; `buildPaymentReminderMessage` + `PaymentReminderMessage` (Task 2) ; `ReminderChannel`, `availableReminderChannels`, `reminderUriFor` (Task 4) ; `FrenchDate.frenchMonthYear` ; `Lease` (rentAmountCents, totalChargesCents, startDate, paymentDay) ; `Tenant` (email, phone, firstName).
- Produces : `PaymentReminderButton` widget.

Le widget prend le contexte déjà chargé par la fiche bail. Pour rester testable sans ouvrir réellement une app, il accepte une fonction `launcher` injectable (défaut = `url_launcher.launchUrl`).

- [ ] **Step 1: Ajouter les clés i18n**

Dans `lib/l10n/app_en.arb` (template, avec `@description`) puis `lib/l10n/app_fr.arb` :

```json
// app_en.arb
"paymentReminderButton": "Send a reminder",
"@paymentReminderButton": {"description": "Button on the lease detail page (shown when rent is overdue) that lets the landlord send an amicable payment reminder to the tenant"},
"paymentReminderChannelSheetTitle": "Send the reminder via",
"@paymentReminderChannelSheetTitle": {"description": "Title of the bottom sheet letting the landlord pick a channel (email/SMS/WhatsApp) for the payment reminder"},
"paymentReminderChannelEmail": "Email",
"@paymentReminderChannelEmail": {"description": "Payment reminder channel: email"},
"paymentReminderChannelSms": "SMS",
"@paymentReminderChannelSms": {"description": "Payment reminder channel: SMS"},
"paymentReminderChannelWhatsApp": "WhatsApp",
"@paymentReminderChannelWhatsApp": {"description": "Payment reminder channel: WhatsApp"},
"paymentReminderLaunchError": "Could not open the messaging app.",
"@paymentReminderLaunchError": {"description": "SnackBar shown when launchUrl fails to open the mail/SMS/WhatsApp app for a payment reminder"}
```

```json
// app_fr.arb
"paymentReminderButton": "Relancer le locataire",
"paymentReminderChannelSheetTitle": "Envoyer la relance via",
"paymentReminderChannelEmail": "E-mail",
"paymentReminderChannelSms": "SMS",
"paymentReminderChannelWhatsApp": "WhatsApp",
"paymentReminderLaunchError": "Impossible d'ouvrir l'application de messagerie."
```

- [ ] **Step 2: Régénérer l10n + parité**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter gen-l10n && flutter test test/l10n/arb_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Écrire le widget**

`lib/features/leases/presentation/widgets/payment_reminder_button.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../tenants/domain/tenant.dart';
import '../../domain/lease.dart';
import '../../domain/lease_lateness.dart';
import '../../domain/payment_reminder_channel.dart';
import '../../domain/payment_reminder_message.dart';

/// Signature du lanceur d'URL (injectable pour les tests).
typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Bouton « Relancer le locataire » (FEAT-031 V1). À monter uniquement quand
/// le bail est en retard. Ouvre l'app email/SMS/WhatsApp du bailleur avec un
/// message de relance amiable pré-rempli (aucun envoi serveur).
class PaymentReminderButton extends StatelessWidget {
  const PaymentReminderButton({
    super.key,
    required this.lease,
    required this.tenant,
    required this.landlordFullName,
    required this.propertyAddress,
    UrlLauncher? launcher,
    DateTime? now,
  }) : _launcher = launcher ?? launchUrl,
       _now = now;

  final Lease lease;
  final Tenant tenant;
  final String landlordFullName;
  final String propertyAddress;
  final UrlLauncher _launcher;
  final DateTime? _now;

  PaymentReminderMessage _message() {
    final due = leaseCurrentDueMonth(
      startDate: lease.startDate,
      paymentDay: lease.paymentDay,
      now: _now ?? DateTime.now(),
    );
    final dueLabel = due != null
        ? FrenchDate.frenchMonthYear(due)
        : FrenchDate.frenchMonthYear(_now ?? DateTime.now());
    return buildPaymentReminderMessage(
      tenantFirstName: tenant.firstName,
      landlordFullName: landlordFullName,
      propertyAddress: propertyAddress,
      dueMonthLabel: dueLabel,
      amountDueCents: lease.rentAmountCents + lease.totalChargesCents,
    );
  }

  String _channelLabel(BuildContext context, ReminderChannel c) =>
      switch (c) {
        ReminderChannel.email => context.l10n.paymentReminderChannelEmail,
        ReminderChannel.sms => context.l10n.paymentReminderChannelSms,
        ReminderChannel.whatsApp =>
          context.l10n.paymentReminderChannelWhatsApp,
      };

  IconData _channelIcon(ReminderChannel c) => switch (c) {
    ReminderChannel.email => Icons.email_outlined,
    ReminderChannel.sms => Icons.sms_outlined,
    ReminderChannel.whatsApp => Icons.chat_outlined,
  };

  Future<void> _launch(BuildContext context, ReminderChannel channel) async {
    final uri = reminderUriFor(
      channel: channel,
      tenantEmail: tenant.email,
      tenantPhone: tenant.phone,
      message: _message(),
    );
    if (uri == null) return;
    var ok = false;
    try {
      ok = await _launcher(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.paymentReminderLaunchError)),
      );
    }
  }

  Future<void> _onPressed(BuildContext context) async {
    final channels = availableReminderChannels(phone: tenant.phone);
    if (channels.length == 1) {
      await _launch(context, channels.first);
      return;
    }
    final chosen = await showModalBottomSheet<ReminderChannel>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.paymentReminderChannelSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final c in channels)
              ListTile(
                key: Key('reminder_channel_${c.name}'),
                leading: Icon(_channelIcon(c)),
                title: Text(_channelLabel(sheetContext, c)),
                onTap: () => Navigator.of(sheetContext).pop(c),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && context.mounted) {
      await _launch(context, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('btn_payment_reminder'),
      icon: const Icon(Icons.notifications_active_outlined, size: 18),
      label: Text(context.l10n.paymentReminderButton),
      onPressed: () => _onPressed(context),
    );
  }
}
```

> `context.l10n` provient de l'extension `core/i18n/l10n_extensions.dart` (déjà utilisée par `lease_detail_page.dart`). Vérifier le chemin d'import relatif exact depuis ce fichier (profondeur `presentation/widgets/`), calquer sur un widget voisin (`charge_regularization_section.dart` importe `../../../../core/i18n/l10n_extensions.dart`).

- [ ] **Step 4: Monter le bouton dans la fiche bail**

Dans `lib/features/leases/presentation/lease_detail_page.dart`, le `build` de `_LeaseDetailContentState` a déjà `asyncTenant`, `asyncProperty`, `isLate`, `property`. Il faut :
1. récupérer le `Tenant` complet, le `landlordFullName` et le `propertyAddress` pour le bouton. Ré-introduire les valeurs nécessaires (elles avaient été retirées quand elles n'étaient plus utilisées) :

```dart
final tenant = asyncTenant.valueOrNull;
final landlordProfile = ref.watch(landlordProfileProvider).valueOrNull;
```

Ré-ajouter les imports si nécessaire : `../../profile/application/landlord_profile_provider.dart` et `../../../core/utils/property_address.dart` (pour `composePropertyAddress`), plus `../../tenants/domain/tenant.dart` si non importé, et le nouveau `widgets/payment_reminder_button.dart`.

2. Monter le bouton juste après `_StatusCard`, uniquement si en retard et si le contexte est chargé :

```dart
_StatusCard(lease: lease, isLate: isLate),
if (isLate && tenant != null)
  Padding(
    padding: const EdgeInsets.only(top: 12),
    child: PaymentReminderButton(
      lease: lease,
      tenant: tenant,
      landlordFullName: landlordProfile?.fullName ?? '',
      propertyAddress: composePropertyAddress(
        address: property?.address,
        postalCode: property?.postalCode,
        city: property?.city,
      ),
    ),
  ),
const SizedBox(height: 16),
```

- [ ] **Step 5: Écrire le test widget**

`test/widget/payment_reminder_button_test.dart` — pumpe le bouton avec un `launcher` factice qui capture l'`Uri`, et vérifie : email seul (pas de bottom sheet) quand `phone` vide ; ouverture d'un `mailto:` ; présence des 3 canaux quand `phone` FR. S'inspirer d'un test widget existant pour le harnais MaterialApp + l10n (`test/widget/charge_regularization_section_test.dart`).

```dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/widgets/payment_reminder_button.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

Lease _lease() => Lease(
  // Renseigner les champs requis du modèle Lease (copier un factory de test
  // existant, cf. autre test de leases). startDate ancienne + paymentDay pour
  // qu'un mois soit dû. Montants : rent 80000, charges via totalChargesCents.
  // ... (reprendre le constructeur réel de Lease du repo)
);

Tenant _tenant({String? phone}) => Tenant(
  // idem : champs requis (id, firstName 'Marie', lastName, email 'loc@ex.fr',
  // phone). Copier un factory de test Tenant existant.
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('téléphone vide → email direct (mailto), pas de bottom sheet',
      (tester) async {
    Uri? launched;
    await tester.pumpWidget(_host(PaymentReminderButton(
      lease: _lease(),
      tenant: _tenant(phone: null),
      landlordFullName: 'Jean Bailleur',
      propertyAddress: '2 rue de Lyon',
      launcher: (uri, {mode = LaunchMode.platformDefault}) async {
        launched = uri;
        return true;
      },
    )));
    await tester.tap(find.byKey(const Key('btn_payment_reminder')));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer la relance via'), findsNothing);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, 'loc@ex.fr');
  });

  testWidgets('téléphone FR → bottom sheet avec 3 canaux', (tester) async {
    await tester.pumpWidget(_host(PaymentReminderButton(
      lease: _lease(),
      tenant: _tenant(phone: '06 12 34 56 78'),
      landlordFullName: 'Jean Bailleur',
      propertyAddress: '2 rue de Lyon',
      launcher: (uri, {mode = LaunchMode.platformDefault}) async => true,
    )));
    await tester.tap(find.byKey(const Key('btn_payment_reminder')));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer la relance via'), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_email')), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_sms')), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_whatsApp')), findsOneWidget);
  });
}
```

> Reprendre les **factories réels** de `Lease` et `Tenant` depuis un test existant (`grep -rl "Lease(" test/`, `grep -rl "Tenant(" test/`) pour renseigner tous les champs requis — ne pas inventer la forme du constructeur. `startDate` doit être assez ancienne (+ `paymentDay`) pour qu'un mois soit dû, mais le test n'assert pas la période, seulement le canal/URI.

- [ ] **Step 6: Analyse + tests**

Run: `export PATH="/opt/homebrew/bin:$PATH"; flutter analyze lib/features/leases test/widget/payment_reminder_button_test.dart && flutter test test/widget/payment_reminder_button_test.dart test/l10n/arb_parity_test.dart`

- [ ] **Step 7: Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"; dart format lib/features/leases lib/l10n test/widget/payment_reminder_button_test.dart
git add lib/features/leases/presentation/widgets/payment_reminder_button.dart lib/features/leases/presentation/lease_detail_page.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb test/widget/payment_reminder_button_test.dart
git commit -m "feat(leases): bouton Relancer le locataire (email/SMS/WhatsApp) sur bail en retard (FEAT-031)"
```

---

## Task 6 — Documentation d'état

**Files:**
- Modify: `docs/state/routes/leases.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`

- [ ] **Step 1: routes/leases.md** — documenter le bouton « Relancer le locataire » sur la fiche bail (visible si `isLate`), canaux email/SMS/WhatsApp, 100 % client (mailto/sms/wa.me via `launchUrl`), aucun backend.

- [ ] **Step 2: FEATURES.md** — `FEAT-031` → `✅ done` (domaine `leases`), libellé précisé : « Relance de paiement assistée (client-side) — automatisation cron = V2 ».

- [ ] **Step 3: CHANGELOG.md** — entrée FEAT-031 V1 : bouton relance fiche bail, message amiable pré-rempli (mention « pas une mise en demeure »), canaux email/SMS/WhatsApp (WhatsApp FR only), zéro backend/secret, V2 = automatisation serveur (nécessite enabler email).

- [ ] **Step 4: Commit**

```bash
git add docs/state/routes/leases.md docs/state/FEATURES.md docs/state/CHANGELOG.md
git commit -m "docs(state): FEAT-031 V1 relance assistée (routes + FEATURES + CHANGELOG)"
```

---

## Final verification (avant finishing-a-development-branch)

- [ ] `export PATH="/opt/homebrew/bin:$PATH"; flutter analyze` → No issues found.
- [ ] `export PATH="/opt/homebrew/bin:$PATH"; flutter test` → tout vert.
- [ ] `export PATH="/opt/homebrew/bin:$PATH"; dart format --output=none --set-exit-if-changed .` → exit 0.
- [ ] Aucun fichier `functions/`, `firestore.rules`, `firestore.indexes.json` modifié (feature 100 % client — rien à déployer côté backend).

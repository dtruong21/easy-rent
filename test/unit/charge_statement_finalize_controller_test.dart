/// Tests de [ChargeRegularizationPdfData.fromStatement] (helper pur) et de
/// l'orchestration [ChargeStatementFinalizeController] (FEAT-033, Task 7).
///
/// **Portée du test d'orchestration** — le rendu PDF réel (polices
/// embarquées, `package:pdf`) et le partage réel (Web Share API / launchUrl)
/// sont volontairement contournés :
/// - le renderer est injecté via [chargeRegularizationPdfRendererProvider],
///   overridé par un faux renderer instantané ;
/// - le partage est intercepté par un faux [WebShareService] (même pattern
///   que `share_receipt_controller_test.dart`).
///
/// Ce qui EST vérifié de façon déterministe : l'ordre des appels au repo
/// (`finalize` → `getById` → ... → `markAsSent`), les arguments transmis à
/// `finalize`/`getById`/`markAsSent`, et les transitions d'état
/// (preparing → shared / idle / error). Ce qui n'est PAS vérifié : le
/// contenu binaire réel du PDF (le renderer étant factice) — hors périmètre
/// de ce test, déjà couvert indépendamment par
/// `charge_regularization_pdf_renderer_test.dart`.
library;

import 'dart:typed_data';

import 'package:easyrent/features/charge_regularization/application/charge_statement_finalize_controller.dart';
import 'package:easyrent/features/charge_regularization/data/charge_statement_repository.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_share_state.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_statement.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _baseJson() => {
  'id': 'cs-1',
  'landlord_id': 'lord1',
  'lease_id': 'l1',
  'property_id': 'p1',
  // Valeurs distinctives et disjointes des unes des autres (aucune n'est une
  // sous-chaîne d'une autre) — permet de vérifier par `contains()` que le
  // message de partage utilise bien CE champ précis du snapshot figé, et pas
  // un autre champ voisin ni une valeur de formulaire externe au décompte.
  'landlord_full_name': 'Paul Bailleur Figé',
  'landlord_address': '1 rue A',
  'tenant_full_name': 'Zoé Locataire',
  'tenant_first_name': 'Mariette',
  'property_name': 'Studio',
  'property_address': '2 rue B',
  'period_start': '2025-01-01T00:00:00.000Z',
  'period_end': '2025-12-31T00:00:00.000Z',
  'provisions_collected_cents': 12000,
  'actual_expenses_cents': 15000,
  'actual_expenses_source': 'manual',
  'balance_cents': 3000,
  'line_items': <dynamic>[],
  'created_at': '2026-01-05T10:00:00.000Z',
  'is_voided': false,
  'voided_at': null,
  'voided_reason': null,
  'sent_at': null,
  'sent_to_email': null,
  'schema_version': 1,
};

// ---------------------------------------------------------------------------
// Fake repository — enregistre l'ordre et les arguments des appels.
// ---------------------------------------------------------------------------

class _FakeChargeStatementRepository implements ChargeStatementRepository {
  final List<String> calls = [];

  ChargeStatementFinalizeResult? finalizeResult;
  ChargeStatement? statementToReturn;
  Exception? finalizeException;
  Exception? markAsSentException;

  // Arguments capturés du dernier appel.
  String? finalizeLeaseId;
  DateTime? finalizePeriodStart;
  DateTime? finalizePeriodEnd;
  int? finalizeActualExpensesCents;
  String? finalizeActualExpensesSource;
  List<Map<String, dynamic>>? finalizeLineItems;
  String? getByIdArg;
  String? markAsSentId;
  String? markAsSentEmail;

  @override
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource,
    required List<Map<String, dynamic>> lineItems,
  }) async {
    calls.add('finalize');
    finalizeLeaseId = leaseId;
    finalizePeriodStart = periodStart;
    finalizePeriodEnd = periodEnd;
    finalizeActualExpensesCents = actualExpensesCents;
    finalizeActualExpensesSource = actualExpensesSource;
    finalizeLineItems = lineItems;
    if (finalizeException != null) throw finalizeException!;
    return finalizeResult!;
  }

  @override
  Future<ChargeStatement> getById(String id) async {
    calls.add('getById');
    getByIdArg = id;
    return statementToReturn!;
  }

  @override
  Future<void> markAsSent({required String id, String? email}) async {
    calls.add('markAsSent');
    markAsSentId = id;
    markAsSentEmail = email;
    if (markAsSentException != null) throw markAsSentException!;
  }

  @override
  Future<void> voidStatement(String id, String reason) async =>
      throw UnimplementedError();

  @override
  Future<List<ChargeStatement>> listForLease(String leaseId) async => [];
}

// ---------------------------------------------------------------------------
// Fake WebShareService — même pattern que share_receipt_controller_test.dart
// ---------------------------------------------------------------------------

class _FakeWebShare implements WebShareService {
  final bool _canShare;
  final Exception? _shareException;

  bool sharePdfCalled = false;
  String? lastFilename;
  String? lastTitle;
  String? lastText;

  _FakeWebShare({bool canShare = true, Exception? shareException})
    : _canShare = canShare,
      _shareException = shareException;

  @override
  bool canShareFiles() => _canShare;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    sharePdfCalled = true;
    lastFilename = filename;
    lastTitle = title;
    lastText = text;
    if (_shareException != null) throw _shareException;
  }

  @override
  Future<bool> copyToClipboard(String text) async => true;

  @override
  Future<List<int>> fetchBytes(String url) async => const [];

  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async => false;

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {}
}

// ---------------------------------------------------------------------------
// Faux renderer — évite le rendu PDF réel (polices embarquées, coûteux).
// ---------------------------------------------------------------------------

Future<Uint8List> _fakeRenderer(ChargeRegularizationPdfData data) async =>
    Uint8List.fromList(const [1, 2, 3]);

ChargeStatement _makeStatement({String id = 'cs-1'}) =>
    ChargeStatement.fromJson({..._baseJson(), 'id': id});

ChargeStatementFinalizeResult _makeFinalizeResult({String id = 'cs-1'}) =>
    ChargeStatementFinalizeResult(
      statementId: id,
      balanceCents: 3000,
      direction: 'dueByTenant',
    );

ProviderContainer _makeContainer({
  required _FakeChargeStatementRepository repo,
  required _FakeWebShare webShare,
}) {
  return ProviderContainer(
    overrides: [
      chargeStatementRepositoryProvider.overrideWithValue(repo),
      webShareServiceProvider.overrideWithValue(webShare),
      chargeRegularizationPdfRendererProvider.overrideWithValue(_fakeRenderer),
    ],
  );
}

const _leaseId = 'lease-1';

void main() {
  group('ChargeRegularizationPdfData.fromStatement', () {
    test('construit un PdfData depuis les champs figés', () {
      final s = ChargeStatement.fromJson(_baseJson());
      final d = ChargeRegularizationPdfData.fromStatement(s);

      expect(d.landlordFullName, s.landlordFullName);
      expect(d.landlordAddress, s.landlordAddress);
      expect(d.tenantFullName, s.tenantFullName);
      expect(d.propertyAddress, s.propertyAddress);
      expect(d.balance.periodStart, s.periodStart);
      expect(d.balance.periodEnd, s.periodEnd);
      expect(d.balance.provisionsCollectedCents, s.provisionsCollectedCents);
      expect(d.balance.actualExpensesCents, s.actualExpensesCents);
      // le PDF re-rendu reflète la date de finalisation figée.
      expect(d.generatedAt, s.createdAt);
    });
  });

  group('ChargeStatementFinalizeController.finalizeAndShare', () {
    late _FakeChargeStatementRepository repo;

    setUp(() {
      repo = _FakeChargeStatementRepository()
        ..finalizeResult = _makeFinalizeResult()
        ..statementToReturn = _makeStatement();
    });

    test(
      'happy path : finalize → getById → partage → markAsSent, state=shared',
      () async {
        final webShare = _FakeWebShare(canShare: true);
        final container = _makeContainer(repo: repo, webShare: webShare);
        addTearDown(container.dispose);

        await container
            .read(chargeStatementFinalizeControllerProvider.notifier)
            .finalizeAndShare(
              leaseId: _leaseId,
              periodStart: DateTime.utc(2025, 1, 1),
              periodEnd: DateTime.utc(2025, 12, 31),
              actualExpensesCents: 15000,
              actualExpensesSource: 'manual',
              lineItems: const [],
              tenantEmail: 'loc@example.com',
            );

        // Ordre des appels : finalize puis getById puis (après partage)
        // markAsSent — chacun appelé une seule fois.
        expect(repo.calls, ['finalize', 'getById', 'markAsSent']);

        // Arguments transmis à finalize.
        expect(repo.finalizeLeaseId, 'lease-1');
        expect(repo.finalizePeriodStart, DateTime.utc(2025, 1, 1));
        expect(repo.finalizePeriodEnd, DateTime.utc(2025, 12, 31));
        expect(repo.finalizeActualExpensesCents, 15000);
        expect(repo.finalizeActualExpensesSource, 'manual');
        expect(repo.finalizeLineItems, const []);

        // getById relit bien le statementId retourné par finalize.
        expect(repo.getByIdArg, 'cs-1');

        // markAsSent appelé avec l'id du décompte figé et l'email locataire.
        expect(repo.markAsSentId, 'cs-1');
        expect(repo.markAsSentEmail, 'loc@example.com');

        expect(webShare.sharePdfCalled, isTrue);

        // Régression ciblée (review round 1) : le message de partage (titre
        // du partage natif + corps mailto:/Web Share) DOIT provenir du
        // snapshot figé relu (`statement`), jamais d'un quelconque paramètre
        // de formulaire — `finalizeAndShare` n'en accepte d'ailleurs plus
        // aucun pour l'identité (landlord/tenant/adresse). On vérifie ici
        // que ce sont bien les valeurs de `repo.statementToReturn` (nom
        // distinctif `'Paul Bailleur Figé'` / `'Mariette'`, jamais passées
        // en paramètre à cet appel) qui apparaissent dans le message envoyé.
        expect(webShare.lastText, contains('Mariette'));
        expect(webShare.lastText, contains('Paul Bailleur Figé'));
        expect(webShare.lastText, isNot(contains('Zoé Locataire')));

        final state = container.read(chargeStatementFinalizeControllerProvider);
        expect(state, isA<ChargeRegularizationShareShared>());
        if (state case ChargeRegularizationShareShared(
          :final usedNativeShare,
        )) {
          expect(usedNativeShare, isTrue);
        }
      },
    );

    test('ShareAbortedException → idle, markAsSent jamais appelé', () async {
      final webShare = _FakeWebShare(
        canShare: true,
        shareException: const ShareAbortedException(),
      );
      final container = _makeContainer(repo: repo, webShare: webShare);
      addTearDown(container.dispose);

      await container
          .read(chargeStatementFinalizeControllerProvider.notifier)
          .finalizeAndShare(
            leaseId: _leaseId,
            periodStart: DateTime.utc(2025, 1, 1),
            periodEnd: DateTime.utc(2025, 12, 31),
            actualExpensesCents: 15000,
            actualExpensesSource: 'manual',
            lineItems: const [],
          );

      expect(repo.calls, ['finalize', 'getById']);
      expect(repo.calls, isNot(contains('markAsSent')));
      expect(
        container.read(chargeStatementFinalizeControllerProvider),
        isA<ChargeRegularizationShareIdle>(),
      );
    });

    test(
      'ShareReceiptException → state error, markAsSent jamais appelé',
      () async {
        final webShare = _FakeWebShare(
          canShare: true,
          shareException: const ShareReceiptException('DOM error'),
        );
        final container = _makeContainer(repo: repo, webShare: webShare);
        addTearDown(container.dispose);

        await container
            .read(chargeStatementFinalizeControllerProvider.notifier)
            .finalizeAndShare(
              leaseId: _leaseId,
              periodStart: DateTime.utc(2025, 1, 1),
              periodEnd: DateTime.utc(2025, 12, 31),
              actualExpensesCents: 15000,
              actualExpensesSource: 'manual',
              lineItems: const [],
            );

        expect(repo.calls, isNot(contains('markAsSent')));
        expect(
          container.read(chargeStatementFinalizeControllerProvider),
          isA<ChargeRegularizationShareError>(),
        );
      },
    );

    test('erreur de finalize() → state error, getById jamais appelé', () async {
      repo.finalizeException = Exception('callable failed');
      final webShare = _FakeWebShare(canShare: true);
      final container = _makeContainer(repo: repo, webShare: webShare);
      addTearDown(container.dispose);

      await container
          .read(chargeStatementFinalizeControllerProvider.notifier)
          .finalizeAndShare(
            leaseId: _leaseId,
            periodStart: DateTime.utc(2025, 1, 1),
            periodEnd: DateTime.utc(2025, 12, 31),
            actualExpensesCents: 15000,
            actualExpensesSource: 'manual',
            lineItems: const [],
          );

      expect(repo.calls, ['finalize']);
      expect(
        container.read(chargeStatementFinalizeControllerProvider),
        isA<ChargeRegularizationShareError>(),
      );
    });
  });

  group('ChargeStatementFinalizeController.shareExisting', () {
    test('re-partage sans re-finaliser : finalize jamais appelé', () async {
      final repo = _FakeChargeStatementRepository();
      final webShare = _FakeWebShare(canShare: true);
      final container = _makeContainer(repo: repo, webShare: webShare);
      addTearDown(container.dispose);

      final statement = _makeStatement(id: 'cs-existing');

      await container
          .read(chargeStatementFinalizeControllerProvider.notifier)
          .shareExisting(statement, tenantEmail: 'loc@example.com');

      expect(repo.calls, ['markAsSent']);
      expect(repo.markAsSentId, 'cs-existing');
      expect(repo.markAsSentEmail, 'loc@example.com');
      expect(webShare.sharePdfCalled, isTrue);
      expect(
        container.read(chargeStatementFinalizeControllerProvider),
        isA<ChargeRegularizationShareShared>(),
      );
    });

    test('re-partage d\'un décompte VOIDÉ : shared, markAsSent jamais appelé '
        '(régression revue finale — évite le faux snackbar d\'erreur, '
        '`markChargeStatementAsSent` levant `failed-precondition` côté '
        'serveur sur un décompte annulé)', () async {
      final repo = _FakeChargeStatementRepository();
      final webShare = _FakeWebShare(canShare: true);
      final container = _makeContainer(repo: repo, webShare: webShare);
      addTearDown(container.dispose);

      final voidedStatement = ChargeStatement.fromJson({
        ..._baseJson(),
        'id': 'cs-voided',
        'is_voided': true,
        'voided_reason': 'erreur de saisie',
      });

      await container
          .read(chargeStatementFinalizeControllerProvider.notifier)
          .shareExisting(voidedStatement, tenantEmail: 'loc@example.com');

      expect(repo.calls, isEmpty);
      expect(webShare.sharePdfCalled, isTrue);
      expect(
        container.read(chargeStatementFinalizeControllerProvider),
        isA<ChargeRegularizationShareShared>(),
      );
    });
  });
}

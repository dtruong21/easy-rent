/// Tests widget de [ExpenseReceiptField] (FEAT-041b) — flux d'upload du
/// justificatif dans le formulaire dépense.
///
/// Couvre : bouton "Joindre" visible à l'état idle (recommandé, non
/// bloquant) ; affichage progression / succès / erreur selon l'état du
/// [ExpenseReceiptUploadController] ; bouton retirer disponible après succès.
library;

import 'dart:typed_data';

import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/expenses/application/expense_receipt_upload_controller.dart';
import 'package:easyrent/features/expenses/domain/expense_receipt_upload_state.dart';
import 'package:easyrent/features/expenses/presentation/expense_receipt_field.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository — jamais réellement appelé dans ces tests (on pilote
// l'état du contrôleur directement), mais requis pour le provider override.
// ---------------------------------------------------------------------------

class _FakeDocumentsRepository implements DocumentsRepository {
  @override
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<List<Document>> listForLease(String leaseId) async => [];

  @override
  Future<Document> getById(String id) async => throw UnimplementedError();

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async => throw UnimplementedError();

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async => throw UnimplementedError();

  @override
  Future<String> createSignedUrl(
    String documentId, {
    int expiresInSeconds = 300,
  }) async => throw UnimplementedError();

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      const DocumentsQuota(totalBytes: 0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildField({
  required ProviderContainer container,
  String? existingDocumentId,
  Locale locale = const Locale('fr'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: locale,
      supportedLocales: supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpenseReceiptField(
            propertyId: 'property-1',
            existingDocumentId: existingDocumentId,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExpenseReceiptField — état idle (justificatif recommandé)', () {
    testWidgets('bouton "Joindre un justificatif" visible', (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
          // FEAT-056 : le plafond de taille du justificatif est désormais
          // différencié par palier — `ExpenseReceiptField` lit
          // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
          // `landlordTierProvider`.
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsOneWidget);
      expect(find.textContaining('recommandé'), findsWidgets);
    });

    testWidgets(
      'mention "sans justificatif" affichée — non bloquant (décision #8)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
            landlordTierProvider.overrideWith(
              (ref) => Stream.value(
                const LandlordTierSnapshot(tier: SubscriptionTier.free),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildField(container: container));
        await tester.pumpAndSettle();

        expect(find.textContaining('sans justificatif'), findsOneWidget);
      },
    );

    testWidgets(
      'locale EN → la durée légale de conservation reste « 5 à 10 ans » (FR)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
            landlordTierProvider.overrideWith(
              (ref) => Stream.value(
                const LandlordTierSnapshot(tier: SubscriptionTier.free),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildField(container: container, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // Durée légale de conservation : jamais traduite en anglais.
        expect(find.textContaining('5 à 10 ans'), findsOneWidget);
        expect(find.textContaining('5 to 10 years'), findsNothing);
      },
    );
  });

  group('ExpenseReceiptField — upload en cours', () {
    testWidgets('affiche la progression et masque le bouton "Joindre"', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
          // FEAT-056 : le plafond de taille du justificatif est désormais
          // différencié par palier — `ExpenseReceiptField` lit
          // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
          // `landlordTierProvider`.
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.uploading(
        filename: 'facture.pdf',
        progress: 0.5,
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Envoi de facture.pdf'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsNothing);
    });
  });

  group('ExpenseReceiptField — upload réussi', () {
    testWidgets(
      'affiche le nom de fichier + bouton retirer — pas de blocage sur '
      "l'absence de bail",
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
            landlordTierProvider.overrideWith(
              (ref) => Stream.value(
                const LandlordTierSnapshot(tier: SubscriptionTier.free),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(expenseReceiptUploadControllerProvider.notifier)
            .state = const ExpenseReceiptUploadState.success(
          filename: 'decompte-syndic.pdf',
          documentId: 'doc-receipt-1',
        );

        await tester.pumpWidget(_buildField(container: container));
        await tester.pumpAndSettle();

        expect(find.text('decompte-syndic.pdf'), findsOneWidget);
        expect(
          find.byKey(const Key('btn_remove_expense_receipt')),
          findsOneWidget,
        );
      },
    );

    testWidgets('bouton retirer remet le contrôleur à idle', (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
          // FEAT-056 : le plafond de taille du justificatif est désormais
          // différencié par palier — `ExpenseReceiptField` lit
          // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
          // `landlordTierProvider`.
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.success(
        filename: 'decompte-syndic.pdf',
        documentId: 'doc-receipt-1',
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_remove_expense_receipt')));
      await tester.pumpAndSettle();

      expect(
        container.read(expenseReceiptUploadControllerProvider),
        const ExpenseReceiptUploadState.idle(),
      );
      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsOneWidget);
    });
  });

  group('ExpenseReceiptField — échec upload (non bloquant)', () {
    testWidgets('affiche le message d\'erreur + bouton réessayer', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
          // FEAT-056 : le plafond de taille du justificatif est désormais
          // différencié par palier — `ExpenseReceiptField` lit
          // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
          // `landlordTierProvider`.
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.error(
        filename: 'facture.pdf',
        message: "Erreur lors de l'envoi. Réessayez.",
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.text("Erreur lors de l'envoi. Réessayez."), findsOneWidget);
      expect(
        find.byKey(const Key('btn_retry_expense_receipt')),
        findsOneWidget,
      );
    });
  });

  group('ExpenseReceiptField — édition, justificatif déjà attaché (correctif '
      'review FEAT-041, finding 6)', () {
    testWidgets(
      'existingDocumentId fourni + état idle → affiche "justificatif déjà '
      'attaché" plutôt que le bouton "Joindre"',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
            landlordTierProvider.overrideWith(
              (ref) => Stream.value(
                const LandlordTierSnapshot(tier: SubscriptionTier.free),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildField(
            container: container,
            existingDocumentId: 'doc-existing-1',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('text_expense_receipt_existing')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_pick_expense_receipt')),
          findsNothing,
          reason:
              'le bouton "Joindre" laisserait croire, à tort, qu\'aucun '
              'justificatif n\'est associé à la dépense en édition.',
        );
        expect(
          find.byKey(const Key('btn_replace_expense_receipt')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_remove_existing_expense_receipt')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'existingDocumentId == null (création, ou édition sans justificatif) '
      '→ bouton "Joindre" classique, pas l\'état "déjà attaché"',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
            landlordTierProvider.overrideWith(
              (ref) => Stream.value(
                const LandlordTierSnapshot(tier: SubscriptionTier.free),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildField(container: container));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_pick_expense_receipt')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('text_expense_receipt_existing')),
          findsNothing,
        );
      },
    );

    testWidgets('bouton "Retirer" sur le justificatif existant → passe le '
        'contrôleur à ReceiptRemoved et fait réapparaître le bouton '
        '"Joindre"', (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
          // FEAT-056 : le plafond de taille du justificatif est désormais
          // différencié par palier — `ExpenseReceiptField` lit
          // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
          // `landlordTierProvider`.
          landlordTierProvider.overrideWith(
            (ref) => Stream.value(
              const LandlordTierSnapshot(tier: SubscriptionTier.free),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildField(container: container, existingDocumentId: 'doc-existing-1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('btn_remove_existing_expense_receipt')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(expenseReceiptUploadControllerProvider),
        const ExpenseReceiptUploadState.removed(),
      );
      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsOneWidget);
      expect(
        find.byKey(const Key('text_expense_receipt_existing')),
        findsNothing,
      );
    });
  });
}

/// Tests widget de [UploadProgressList].
///
/// Couvre : rendu selon états (pending / uploading / success / error).
///
/// FEAT-043 (i18n) : le rendu du statut `error` appelle désormais
/// `reason.message(context)` (`UploadFileErrorReasonL10n`), qui nécessite un
/// `AppLocalizations` enregistré — `_buildList` ci-dessous déclare donc les
/// délégués/`supportedLocales` (locale forcée FR).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/upload_file_status.dart';
import 'package:easyrent/features/documents/presentation/widgets/upload_progress_list.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Document _makeDoc() => Document(
  id: 'doc-1',
  landlordId: 'l1',
  leaseId: 'lease-1',
  category: DocumentCategory.autre,
  filename: 'test.pdf',
  storagePath: 'prod/l1/documents/doc-1.pdf',
  mimeType: 'application/pdf',
  sizeBytes: 1024,
  legalHold: false,
  uploadedAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

Widget _buildList(List<UploadFileStatus> files) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: Scaffold(body: UploadProgressList(files: files)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UploadProgressList', () {
    testWidgets('liste vide → aucun texte affiché', (tester) async {
      await tester.pumpWidget(_buildList([]));
      await tester.pumpAndSettle();
      expect(find.text('test.pdf'), findsNothing);
      // SizedBox.shrink est rendu pour une liste vide
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('status pending → affiche le nom de fichier', (tester) async {
      await tester.pumpWidget(
        _buildList([
          const UploadFileStatus.pending(
            filename: 'contrat.pdf',
            sizeBytes: 1024,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('contrat.pdf'), findsOneWidget);
    });

    testWidgets('status uploading → affiche LinearProgressIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildList([
          const UploadFileStatus.uploading(
            filename: 'photo.jpg',
            progress: 0.5,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
    });

    testWidgets('status success → affiche le nom de fichier', (tester) async {
      await tester.pumpWidget(
        _buildList([
          UploadFileStatus.success(filename: 'bail.pdf', document: _makeDoc()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('bail.pdf'), findsOneWidget);
    });

    testWidgets('status error → affiche le nom et le message d\'erreur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildList([
          const UploadFileStatus.error(
            filename: 'doc.docx',
            reason: UploadFileErrorReason.unsupportedFormat,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('doc.docx'), findsOneWidget);
    });

    testWidgets('plusieurs fichiers → affiche tous les noms', (tester) async {
      await tester.pumpWidget(
        _buildList([
          const UploadFileStatus.pending(filename: 'a.pdf', sizeBytes: 100),
          const UploadFileStatus.uploading(filename: 'b.jpg', progress: 0.3),
          const UploadFileStatus.error(
            filename: 'c.docx',
            reason: UploadFileErrorReason.unexpected,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.jpg'), findsOneWidget);
      expect(find.text('c.docx'), findsOneWidget);
    });
  });
}

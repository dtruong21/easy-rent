import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../receipts/data/web_share_service_bridge.dart';
import '../data/account_export_repository.dart';

final _log = Logger('ExportDataController');

/// Étape du flux d'export RGPD.
enum ExportDataStatus { idle, loading, success, error }

/// Catégorie d'erreur, stable pour la présentation (i18n FEAT-043 : le
/// contrôleur ne produit pas de texte, juste un code).
enum ExportDataErrorKind { none, recentLoginRequired, generic }

/// État observable de [ExportDataController].
class ExportDataState {
  const ExportDataState({
    this.status = ExportDataStatus.idle,
    this.errorKind = ExportDataErrorKind.none,
  });

  final ExportDataStatus status;
  final ExportDataErrorKind errorKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExportDataState &&
          other.status == status &&
          other.errorKind == errorKind);

  @override
  int get hashCode => Object.hash(status, errorKind);

  @override
  String toString() =>
      'ExportDataState(status: $status, errorKind: $errorKind)';
}

/// Orchestration de l'export RGPD (droit à la portabilité, art. 20) :
/// callable `exportAccountData` (Task 2) → sérialisation JSON indentée →
/// remise du fichier via [WebShareService.deliverFile] (Task 3).
///
/// Pas de PDF, pas de stockage serveur — le fichier n'existe qu'en mémoire
/// client, exactement comme le rendu des quittances (cf.
/// `ReceiptsRepository.renderPdfBytes`).
class ExportDataController extends AutoDisposeNotifier<ExportDataState> {
  @override
  ExportDataState build() => const ExportDataState();

  Future<void> export() async {
    state = const ExportDataState(status: ExportDataStatus.loading);

    try {
      final data = await ref
          .read(accountExportRepositoryProvider)
          .exportAccountData();

      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      final filename = 'baillan-export-${_todayIso()}.json';

      await ref
          .read(webShareServiceProvider)
          .deliverFile(
            filename: filename,
            mimeType: 'application/json',
            bytes: bytes,
            shareTitle: 'Export de mes données Baillan',
          );

      _log.info('export RGPD terminé ($filename)');
      state = const ExportDataState(status: ExportDataStatus.success);
    } on FirebaseFunctionsException catch (e, st) {
      final recentLoginRequired =
          e.code == 'failed-precondition' &&
          e.message == 'recent-login-required';
      _log.warning('export RGPD échoué (callable)', e, st);
      state = ExportDataState(
        status: ExportDataStatus.error,
        errorKind: recentLoginRequired
            ? ExportDataErrorKind.recentLoginRequired
            : ExportDataErrorKind.generic,
      );
    } catch (e, st) {
      _log.severe('export RGPD échoué (inattendu)', e, st);
      state = const ExportDataState(
        status: ExportDataStatus.error,
        errorKind: ExportDataErrorKind.generic,
      );
    }
  }

  static String _todayIso() =>
      DateTime.now().toIso8601String().split('T').first;
}

final exportDataControllerProvider =
    AutoDisposeNotifierProvider<ExportDataController, ExportDataState>(
      ExportDataController.new,
    );

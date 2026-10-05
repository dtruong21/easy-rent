import 'package:flutter/widgets.dart';

import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/utils/byte_format.dart';
import '../../paid_plan/presentation/widgets/plan_level_label.dart';
import '../application/upload_documents_controller.dart';
import '../domain/upload_file_status.dart';

/// Traduit un [UploadFileErrorReason] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) —
/// [UploadDocumentsController] (application) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet (identique à
/// `ValidationErrorL10n`/`ProfileFormErrorReasonL10n`).
extension UploadFileErrorReasonL10n on UploadFileErrorReason {
  /// [maxFileSizeBytes] : plafond résolu côté client
  /// (`quotaLimitProvider(PlanQuota.documentMaxBytes)`) — utilisé pour
  /// [fileTooLarge] tant qu'aucun détail serveur n'est disponible.
  ///
  /// [serverLimitBytes]/[serverUpgradeToLevelId] (FEAT-056) : détails
  /// renvoyés par le serveur quand le refus vient de `createDocument` en
  /// course (`FileError.serverLimitBytes`/`serverUpgradeToLevelId`) —
  /// priment sur [maxFileSizeBytes] quand présents, et ajoutent l'upsell
  /// « Passez à … » quand un palier débloquerait le fichier.
  String message(
    BuildContext context, {
    int? maxFileSizeBytes,
    int? serverLimitBytes,
    String? serverUpgradeToLevelId,
  }) {
    final l10n = context.l10n;
    if (this == UploadFileErrorReason.fileTooLarge) {
      final limit = serverLimitBytes ?? maxFileSizeBytes ?? kMaxFileSizeBytes;
      final sizeLabel = ByteFormat.format(limit);
      // Apps iOS/Android : pas d'upsell « Passez à … » (aucun achat hors achat
      // intégré), seulement la taille maximale.
      if (serverUpgradeToLevelId != null && !isStoreApp) {
        return l10n.documentsUploadErrorFileTooLargeWithUpgrade(
          sizeLabel,
          planLevelLabelForId(context, serverUpgradeToLevelId),
        );
      }
      return l10n.documentsUploadErrorFileTooLarge(sizeLabel);
    }
    return switch (this) {
      UploadFileErrorReason.unsupportedFormat =>
        l10n.documentsUploadErrorUnsupportedFormat,
      UploadFileErrorReason.storageError => l10n.documentsUploadErrorStorage,
      UploadFileErrorReason.connectionError => l10n.documentsErrorConnection,
      UploadFileErrorReason.unexpected => l10n.documentsUploadErrorUnexpected,
      UploadFileErrorReason.fileTooLarge => throw StateError('handled above'),
    };
  }
}

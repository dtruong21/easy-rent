import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_item.freezed.dart';

/// Item d'activité récente : union scellée des 3 types d'actions.
///
/// Utilisé par [RecentActivitySection] pour afficher les 5 dernières actions.
@freezed
sealed class ActivityItem with _$ActivityItem {
  /// Un paiement a été enregistré.
  const factory ActivityItem.paymentRecorded({
    required String paymentId,
    required String leaseId,
    required String tenantName,
    required int amountCents,
    required DateTime occurredAt,
  }) = ActivityPaymentRecorded;

  /// Une quittance a été générée.
  const factory ActivityItem.receiptGenerated({
    required String receiptId,
    required String leaseId,
    required String periodLabel,
    required int totalCents,
    required DateTime occurredAt,
  }) = ActivityReceiptGenerated;

  /// Un document a été uploadé.
  const factory ActivityItem.documentUploaded({
    required String documentId,
    required String leaseId,
    required String categoryLabel,
    required String filename,
    required int sizeBytes,
    required DateTime occurredAt,
  }) = ActivityDocumentUploaded;
}

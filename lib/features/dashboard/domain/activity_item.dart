import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_item.freezed.dart';

/// Sentinel FR produit par [DashboardRepository] (pas de `BuildContext`
/// disponible côté `data/`) quand une quittance n'a pas de
/// `periodStart`/`periodEnd` Firestore exploitables (données malformées —
/// cas limite qui ne devrait jamais arriver en pratique). Détecté et
/// relocalisé côté présentation par `RecentActivitySection` (FEAT-043 i18n,
/// même pattern que `LeaseListItemDisplayL10n`).
const String kUnknownPeriodLabelSentinel = 'Période inconnue';

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
  ///
  /// [periodLabel] est soit un intervalle ISO `yyyy-MM-dd → yyyy-MM-dd` (peu
  /// importe la locale, ce ne sont pas des mots), soit
  /// [kUnknownPeriodLabelSentinel] dans le cas limite documenté ci-dessus.
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

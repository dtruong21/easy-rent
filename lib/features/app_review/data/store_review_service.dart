import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/config/env.dart';

/// Notation sur les stores (FEAT-060). Seule [InAppReviewStoreReviewService]
/// importe `in_app_review` ; n'appeler que dans une app store.
abstract interface class StoreReviewService {
  Future<bool> isAvailable();

  /// Fenêtre de note native. Le store décide de l'afficher ou non ; jamais
  /// précédée d'une question (règles Apple 5.6.1 et Google Play).
  Future<void> requestReview();

  /// Ouvre la fiche de l'app (iOS : [appStoreId] requis).
  Future<void> openStoreListing({String? appStoreId});
}

class InAppReviewStoreReviewService implements StoreReviewService {
  final InAppReview _inAppReview = InAppReview.instance;

  @override
  Future<bool> isAvailable() => _inAppReview.isAvailable();

  @override
  Future<void> requestReview() => _inAppReview.requestReview();

  @override
  Future<void> openStoreListing({String? appStoreId}) =>
      _inAppReview.openStoreListing(appStoreId: appStoreId);
}

final storeReviewServiceProvider = Provider<StoreReviewService>(
  (_) => InAppReviewStoreReviewService(),
);

/// « Noter l'app » disponible ? App store uniquement ; sur iOS, seulement
/// avec l'identifiant App Store ([Env.appStoreId]).
bool canRateInStore({
  required bool storeApp,
  required TargetPlatform platform,
  String appStoreId = Env.appStoreId,
}) {
  if (!storeApp) return false;
  if (platform == TargetPlatform.iOS) return appStoreId.trim().isNotEmpty;
  return true;
}

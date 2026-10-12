import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store_billing_service.dart';
import '../domain/store_billing_models.dart';

/// Offre Pro du store (FEAT-044e), relue à chaque ouverture de l'écran
/// d'achat. `null` = indisponible.
final storeProOfferProvider = FutureProvider.autoDispose<ProStoreOffer?>(
  (ref) => ref.read(storeBillingServiceProvider).fetchProOffer(),
);

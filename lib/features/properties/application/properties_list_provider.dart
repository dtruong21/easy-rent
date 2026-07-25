import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/property_repository.dart';
import '../domain/property.dart';
import '../domain/property_list_item.dart';

final _log = Logger('PropertiesListNotifier');

/// Notifier qui charge et expose la liste des biens du landlord courant.
///
/// Expose une méthode [refresh] pour recharger la liste après une action
/// (création, modification, archivage).
class PropertiesListNotifier extends AsyncNotifier<List<Property>> {
  @override
  Future<List<Property>> build() async {
    return _fetch();
  }

  Future<List<Property>> _fetch() async {
    _log.info('fetch properties list');
    return ref.read(propertyRepositoryProvider).list();
  }

  /// Recharge la liste depuis Firestore.
  ///
  /// À appeler après une création, modification ou archivage réussis.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Provider de la liste des biens immobiliers.
final propertiesListProvider =
    AsyncNotifierProvider<PropertiesListNotifier, List<Property>>(
      PropertiesListNotifier.new,
    );

// ---------------------------------------------------------------------------
// Nouveau provider Phase 2 — liste enrichie avec baux actifs
// ---------------------------------------------------------------------------

final _logItems = Logger('PropertiesListItemsNotifier');

/// Notifier qui charge et expose la liste enrichie des biens (avec baux actifs).
///
/// Utilise [PropertyRepository.listWithLeases] pour obtenir les [PropertyListItem].
/// Conserve [propertiesListProvider] intact pour les autres consommateurs.
class PropertiesListItemsNotifier
    extends AsyncNotifier<List<PropertyListItem>> {
  @override
  Future<List<PropertyListItem>> build() async {
    return _fetch();
  }

  Future<List<PropertyListItem>> _fetch() async {
    _logItems.info('fetch properties list items');
    return ref.read(propertyRepositoryProvider).listWithLeases();
  }

  /// Recharge la liste depuis Firestore.
  ///
  /// À appeler après une création, modification ou archivage réussis.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Provider de la liste enrichie des biens immobiliers (Phase 2).
///
/// Nouveau provider — n'affecte pas [propertiesListProvider].
final propertiesListItemsProvider =
    AsyncNotifierProvider<PropertiesListItemsNotifier, List<PropertyListItem>>(
      PropertiesListItemsNotifier.new,
    );

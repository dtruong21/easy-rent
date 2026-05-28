import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/property_repository.dart';
import '../domain/property.dart';

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

  /// Recharge la liste depuis Supabase.
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/property_repository.dart';
import '../domain/property.dart';

final _log = Logger('PropertyDetailNotifier');

/// Notifier qui charge un bien par son [id].
///
/// Lance [PropertyNotFoundException] si les Firestore Rules ne renvoient aucun document
/// (bien archivé, non possédé, ou id inconnu — pas de fuite d'information).
class PropertyDetailNotifier extends FamilyAsyncNotifier<Property, String> {
  @override
  Future<Property> build(String arg) async {
    _log.info('fetch property detail id=$arg');
    return ref.read(propertyRepositoryProvider).getById(arg);
  }

  /// Recharge la fiche depuis Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(propertyRepositoryProvider).getById(arg),
    );
  }
}

/// Provider de la fiche d'un bien, paramétré par l'id.
final propertyDetailProvider =
    AsyncNotifierProviderFamily<PropertyDetailNotifier, Property, String>(
      PropertyDetailNotifier.new,
    );

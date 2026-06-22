import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/property_repository.dart';
import '../domain/heating_type.dart';
import '../domain/property.dart';
import '../domain/property_form_state.dart';
import '../domain/property_type.dart';
import 'properties_list_provider.dart';
import 'property_detail_provider.dart';

final _log = Logger('PropertyFormController');

/// Contrôle le formulaire de création / édition d'un bien.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [propertiesListProvider] et, en mode édition,
/// [propertyDetailProvider(id)] pour que la liste et la fiche soient à jour.
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// du formulaire.
class PropertyFormController extends StateNotifier<PropertyFormState> {
  PropertyFormController(this._ref) : super(const PropertyFormState.idle());

  final Ref _ref;

  /// Soumet le formulaire.
  ///
  /// [initial] : null pour une création, propriété existante pour une édition.
  Future<void> submit({
    Property? initial,
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
  }) async {
    state = const PropertyFormState.submitting();

    try {
      final repo = _ref.read(propertyRepositoryProvider);
      final Property result;

      if (initial == null) {
        // Mode création
        result = await repo.create(
          name: name,
          address: address,
          type: type,
          surfaceM2: surfaceM2,
          postalCode: postalCode,
          city: city,
          rooms: rooms,
          bedrooms: bedrooms,
          floor: floor,
          hasElevator: hasElevator,
          furnished: furnished,
          heatingType: heatingType,
          dpeLetter: dpeLetter,
          dpeValueKwhM2Year: dpeValueKwhM2Year,
          gesLetter: gesLetter,
          constructionYear: constructionYear,
        );
        _log.info('property created id=${result.id}');
      } else {
        // Mode édition — on n'envoie QUE les champs métier
        final updated = initial.copyWith(
          name: name,
          address: address,
          type: type,
          surfaceM2: surfaceM2,
          postalCode: postalCode,
          city: city,
          rooms: rooms,
          bedrooms: bedrooms,
          floor: floor,
          hasElevator: hasElevator,
          furnished: furnished,
          heatingType: heatingType,
          dpeLetter: dpeLetter,
          dpeValueKwhM2Year: dpeValueKwhM2Year,
          gesLetter: gesLetter,
          constructionYear: constructionYear,
        );
        result = await repo.update(updated);
        _log.info('property updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(propertyDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié bien.
      _ref.invalidate(propertiesListProvider);

      state = PropertyFormState.success(property: result);
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de submit', e, st);
      state = PropertyFormState.error(message: mapPostgrestError(e));
    } on PropertyNotFoundException catch (notFound, st) {
      _log.warning('PropertyNotFoundException lors de submit', notFound, st);
      state = const PropertyFormState.error(
        message: 'Bien introuvable. Il a peut-être été archivé.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = const PropertyFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const PropertyFormState.idle();
}

/// Provider autoDispose du contrôleur de formulaire bien.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final propertyFormControllerProvider =
    StateNotifierProvider.autoDispose<
      PropertyFormController,
      PropertyFormState
    >((ref) => PropertyFormController(ref));

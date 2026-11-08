import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/property_repository.dart';
import '../../dashboard/application/dashboard_provider.dart';
import '../domain/heating_type.dart';
import '../domain/property.dart';
import '../domain/property_form_state.dart';
import '../domain/property_submit_error.dart';
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
    // FEAT-017 — Financement & acquisition
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
    // Couleur d'identité — modifiable UNIQUEMENT en édition (`initial` non
    // null). Ignoré en création : le bien affiche immédiatement une couleur
    // automatique via le repli déterministe de `PropertyColorKey.resolve`,
    // sans qu'aucune valeur n'ait besoin d'être envoyée au serveur.
    String? colorKey,
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
          purchasePriceCents: purchasePriceCents,
          purchaseDate: purchaseDate,
          notaryFeesCents: notaryFeesCents,
          isNewProperty: isNewProperty,
          propertyTaxAnnualCents: propertyTaxAnnualCents,
          insurancePnoAnnualCents: insurancePnoAnnualCents,
          condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
          loanPrincipalCents: loanPrincipalCents,
          loanRateBps: loanRateBps,
          loanInsuranceBps: loanInsuranceBps,
          loanDurationMonths: loanDurationMonths,
          loanStartDate: loanStartDate,
          loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
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
          purchasePriceCents: purchasePriceCents,
          purchaseDate: purchaseDate,
          notaryFeesCents: notaryFeesCents,
          isNewProperty: isNewProperty,
          propertyTaxAnnualCents: propertyTaxAnnualCents,
          insurancePnoAnnualCents: insurancePnoAnnualCents,
          condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
          loanPrincipalCents: loanPrincipalCents,
          loanRateBps: loanRateBps,
          loanInsuranceBps: loanInsuranceBps,
          loanDurationMonths: loanDurationMonths,
          loanStartDate: loanStartDate,
          loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
          colorKey: colorKey ?? initial.colorKey,
        );
        result = await repo.update(updated);
        _log.info('property updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(propertyDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié bien.
      // Les deux listes (picker bail + cards « Mes biens ») + dashboard.
      _ref.invalidate(propertiesListProvider);
      _ref.invalidate(propertiesListItemsProvider);
      _ref.invalidate(dashboardProvider);

      state = PropertyFormState.success(property: result);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseFunctionsException submit (code=${e.code})', e, st);
      state = PropertyFormState.error(message: _mapFunctionsError(e).name);
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException submit (code=${e.code})', e, st);
      state = PropertyFormState.error(
        message: PropertySubmitError.connectionError.name,
      );
    } on PropertyNotFoundException catch (notFound, st) {
      _log.warning('PropertyNotFoundException lors de submit', notFound, st);
      state = PropertyFormState.error(
        message: PropertySubmitError.notFound.name,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = PropertyFormState.error(
        message: PropertySubmitError.unknown.name,
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const PropertyFormState.idle();
}

/// Mappe les codes d'erreur des Callables Firebase vers un [PropertySubmitError]
/// (FEAT-043 — équivalent de l'ancien `mapPostgrestError`, désormais sans FR
/// en dur, cf. `property_submit_error.dart`).
PropertySubmitError _mapFunctionsError(FirebaseFunctionsException e) {
  // Les messages métier ("property_has_active_leases", etc.) sont
  // renvoyés en `e.message`. Les codes "permission-denied",
  // "failed-precondition" matchent les HttpsError côté CF.
  final code = e.code;
  final msg = e.message ?? '';
  // FEAT-044 : plafond free-tier atteint (createProperty). Doit être mappé
  // AVANT le fallback saveFailed, sinon l'utilisateur voit un « échec de
  // sauvegarde » générique au lieu de l'invitation à passer Pro.
  if (code == 'resource-exhausted' || msg.contains('property_limit_reached')) {
    return PropertySubmitError.limitReached;
  }
  if (msg.contains('property_has_active_leases')) {
    return PropertySubmitError.hasActiveLeases;
  }
  if (code == 'permission-denied' || code == 'unauthenticated') {
    return PropertySubmitError.permissionDenied;
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return PropertySubmitError.serviceUnavailable;
  }
  return PropertySubmitError.saveFailed;
}

/// Provider autoDispose du contrôleur de formulaire bien.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final propertyFormControllerProvider =
    StateNotifierProvider.autoDispose<
      PropertyFormController,
      PropertyFormState
    >((ref) => PropertyFormController(ref));

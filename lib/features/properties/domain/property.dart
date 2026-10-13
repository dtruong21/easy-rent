// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'heating_type.dart';
import 'property_type.dart';

part 'property.freezed.dart';
part 'property.g.dart';

// Helpers JSON pour PropertyType (utilisés par @JsonKey).
PropertyType _typeFromJson(String value) => PropertyType.fromSql(value);
String _typeToJson(PropertyType type) => type.sqlValue;

// Helpers JSON pour HeatingType (utilisés par @JsonKey).
HeatingType? _heatingFromJson(String? v) => HeatingType.fromSql(v);
String? _heatingToJson(HeatingType? v) => v?.sqlValue;

/// Modèle immutable d'un bien immobilier.
///
/// Mappé directement sur la table `properties` (public + dev).
/// Les colonnes `created_at`, `updated_at` et `deleted_at` sont gérées
/// par les triggers Cloud Functions — ne jamais les inclure dans un payload de création/mise à jour.
///
/// [landlordId] : FK vers `landlords.id`. Ne pas l'envoyer dans un INSERT
/// depuis le client — les Firestore Rules vérifient `landlordId == request.auth.uid`.
@freezed
class Property with _$Property {
  const factory Property({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    required String name,
    required String address,
    @JsonKey(fromJson: _typeFromJson, toJson: _typeToJson)
    required PropertyType type,
    @JsonKey(name: 'surface_m2') double? surfaceM2,
    @JsonKey(name: 'postal_code') String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    @JsonKey(name: 'has_elevator') @Default(false) bool hasElevator,
    @Default(false) bool furnished,
    @JsonKey(
      name: 'heating_type',
      fromJson: _heatingFromJson,
      toJson: _heatingToJson,
    )
    HeatingType? heatingType,
    @JsonKey(name: 'dpe_letter') String? dpeLetter,
    @JsonKey(name: 'dpe_value_kwh_m2_year') int? dpeValueKwhM2Year,
    @JsonKey(name: 'ges_letter') String? gesLetter,
    @JsonKey(name: 'construction_year') int? constructionYear,
    // --- FEAT-017 : Financement & acquisition ---
    @JsonKey(name: 'purchase_price_cents') int? purchasePriceCents,
    @JsonKey(name: 'purchase_date') DateTime? purchaseDate,
    @JsonKey(name: 'notary_fees_cents') int? notaryFeesCents,
    @JsonKey(name: 'is_new_property') @Default(false) bool isNewProperty,
    @JsonKey(name: 'property_tax_annual_cents') int? propertyTaxAnnualCents,
    @JsonKey(name: 'insurance_pno_annual_cents') int? insurancePnoAnnualCents,
    @JsonKey(name: 'condo_fees_non_recoverable_cents')
    int? condoFeesNonRecoverableCents,
    @JsonKey(name: 'loan_principal_cents') int? loanPrincipalCents,
    @JsonKey(name: 'loan_rate_bps') int? loanRateBps,
    @JsonKey(name: 'loan_insurance_bps') int? loanInsuranceBps,
    @JsonKey(name: 'loan_duration_months') int? loanDurationMonths,
    @JsonKey(name: 'loan_start_date') DateTime? loanStartDate,
    @JsonKey(name: 'loan_monthly_payment_override_cents')
    int? loanMonthlyPaymentOverrideCents,
    // --- Couleur d'identité (propagation biens/baux/locataires/paiements/
    // quittances) ---
    //
    // Clé de palette [PropertyColorKey] (`lib/core/ui/theme/property_color.dart`),
    // JAMAIS une couleur brute (le thème résout). `null` = pas encore
    // personnalisée par l'utilisateur (bien créé avant cette fonctionnalité,
    // ou attribution automatique pas encore persistée côté serveur) : les
    // widgets d'affichage doivent TOUJOURS résoudre via
    // `PropertyColorKey.resolve(entityId: property.id, stored: property.colorKey)`
    // plutôt que lire ce champ directement — ne jamais laisser un bien
    // s'afficher sans couleur.
    @JsonKey(name: 'color_key') String? colorKey,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Property;

  factory Property.fromJson(Map<String, dynamic> json) =>
      _$PropertyFromJson(json);
}

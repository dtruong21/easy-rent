// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'landlord_profile.freezed.dart';
part 'landlord_profile.g.dart';

/// Modèle immutable du profil bailleur.
///
/// Mappé sur la table `landlords` (public + dev) — sous-ensemble des colonnes
/// pertinentes pour le profil (exclut `deleted_at` qui ne doit jamais être
/// manipulé côté client).
///
/// [email] et [id] sont immutables : ils viennent de Firebase Auth et ne
/// sont jamais modifiables depuis l'UI.
///
/// [fullName] et [address] sont requis pour générer des quittances (loi
/// 1989 art. 21). [phone] est facultatif.
@freezed
class LandlordProfile with _$LandlordProfile {
  const factory LandlordProfile({
    /// Identifiant Firebase Auth (uid), immutable.
    required String id,

    /// Adresse email du bailleur, immutable (identifiant d'authentification).
    required String email,

    /// Nom complet du bailleur — requis pour les quittances (loi 1989 art. 21).
    @JsonKey(name: 'full_name') String? fullName,

    /// Numéro de téléphone — facultatif.
    String? phone,

    /// Adresse postale du bailleur — requise pour les quittances.
    String? address,

    /// Date de création du compte.
    @JsonKey(name: 'created_at') required DateTime createdAt,

    /// Date de dernière mise à jour (trigger `tr_02_set_updated_at_landlords`).
    @JsonKey(name: 'updated_at') required DateTime updatedAt,

    /// Horodatage du consentement RGPD (accountability art. 7.1 RGPD).
    ///
    /// Renseigné par le trigger [handle_new_user] au moment du signup.
    /// Jamais null après migration FEAT-016 (backfill 'legacy-1' pour l'existant).
    @JsonKey(name: 'rgpd_consent_at') required DateTime rgpdConsentAt,

    /// Version du texte de consentement RGPD présenté à l'utilisateur.
    ///
    /// Valeurs connues : 'v1-2026-06' (texte initial), 'legacy-1' (comptes
    /// antérieurs à FEAT-016, consentement implicite via FEAT-001 UI).
    @JsonKey(name: 'rgpd_consent_version') required String rgpdConsentVersion,
  }) = _LandlordProfile;

  factory LandlordProfile.fromJson(Map<String, dynamic> json) =>
      _$LandlordProfileFromJson(json);
}

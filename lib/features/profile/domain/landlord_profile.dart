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
/// [email] et [id] sont immutables : ils viennent de l'auth Supabase et ne
/// sont jamais modifiables depuis l'UI.
///
/// [fullName] et [address] sont requis pour générer des quittances (loi
/// 1989 art. 21). [phone] est facultatif.
@freezed
class LandlordProfile with _$LandlordProfile {
  const factory LandlordProfile({
    /// Identifiant Supabase Auth (auth.uid()), immutable.
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
  }) = _LandlordProfile;

  factory LandlordProfile.fromJson(Map<String, dynamic> json) =>
      _$LandlordProfileFromJson(json);
}

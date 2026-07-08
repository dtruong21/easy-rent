import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/profile_form_validators.dart';
import '../../../../core/validation/validation_error_l10n.dart';

/// Champs du formulaire profil bailleur.
///
/// - [fullName] et [address] sont obligatoires (loi 1989 art. 21).
/// - [phone] est facultatif.
///
/// Utiliser un [GlobalKey<ProfileFormWidgetState>] pour appeler [validateAll]
/// depuis la page parente avant soumission.
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.formKey,
    required this.fullNameController,
    required this.phoneController,
    required this.addressController,
    this.enabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final bool enabled;

  @override
  State<ProfileForm> createState() => ProfileFormWidgetState();
}

/// State public de [ProfileForm] — exposé pour accès via [GlobalKey].
class ProfileFormWidgetState extends State<ProfileForm> {
  bool _fullNameTouched = false;
  bool _addressTouched = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nom complet (obligatoire — loi 1989 art. 21)
          TextFormField(
            key: const Key('field_full_name'),
            controller: widget.fullNameController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.profileFormFullNameLabel,
              hintText: l10n.profileFormFullNameHint,
              helperText: l10n.profileFormFullNameHelper,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_fullNameTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _fullNameTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_fullNameTouched) return null;
              return ProfileFormValidators.validateFullName(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Téléphone (optionnel)
          TextFormField(
            key: const Key('field_phone'),
            controller: widget.phoneController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.profileFormPhoneLabel,
              hintText: l10n.profileFormPhoneHint,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (v) =>
                ProfileFormValidators.validatePhone(v)?.message(context),
          ),
          const SizedBox(height: 16),

          // Adresse postale (obligatoire — loi 1989 art. 21)
          TextFormField(
            key: const Key('field_address'),
            controller: widget.addressController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.profileFormAddressLabel,
              hintText: l10n.profileFormAddressHint,
              helperText: l10n.profileFormAddressHelper,
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            minLines: 3,
            keyboardType: TextInputType.multiline,
            onChanged: (_) {
              if (_addressTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _addressTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_addressTouched) return null;
              return ProfileFormValidators.validateAddress(v)?.message(context);
            },
          ),
        ],
      ),
    );
  }

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  ///
  /// Appelé par [ProfilePage] lors du tap sur "Enregistrer".
  bool validateAll() {
    setState(() {
      _fullNameTouched = true;
      _addressTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }
}

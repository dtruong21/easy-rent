import 'package:flutter/material.dart';

import '../../../../core/utils/tenant_form_validators.dart';

/// Champs partagés du formulaire locataire.
///
/// Utilisé dans [TenantFormPage] pour la création et l'édition.
/// La validation est déclenchée inline à la perte de focus.
/// Utiliser un [GlobalKey<TenantFormWidgetState>] pour appeler [validateAll].
class TenantForm extends StatefulWidget {
  const TenantForm({
    super.key,
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    this.enabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final bool enabled;

  @override
  State<TenantForm> createState() => TenantFormWidgetState();
}

/// State public de [TenantForm] — exposé pour accès via [GlobalKey].
class TenantFormWidgetState extends State<TenantForm> {
  bool _firstNameTouched = false;
  bool _lastNameTouched = false;
  bool _emailTouched = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Prénom
          TextFormField(
            key: const Key('field_first_name'),
            controller: widget.firstNameController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Prénom *',
              hintText: 'Ex. : Jean',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_firstNameTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _firstNameTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_firstNameTouched) return null;
              return TenantFormValidators.validateFirstName(v);
            },
          ),
          const SizedBox(height: 16),

          // Nom de famille
          TextFormField(
            key: const Key('field_last_name'),
            controller: widget.lastNameController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Nom *',
              hintText: 'Ex. : Dupont',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_lastNameTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _lastNameTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_lastNameTouched) return null;
              return TenantFormValidators.validateLastName(v);
            },
          ),
          const SizedBox(height: 16),

          // Email
          TextFormField(
            key: const Key('field_email'),
            controller: widget.emailController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Email *',
              hintText: 'Ex. : jean.dupont@email.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) {
              if (_emailTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _emailTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_emailTouched) return null;
              return TenantFormValidators.validateEmail(v);
            },
          ),
          const SizedBox(height: 16),

          // Téléphone (optionnel, string libre en V1)
          TextFormField(
            key: const Key('field_phone'),
            controller: widget.phoneController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Téléphone (optionnel)',
              hintText: 'Ex. : 06 12 34 56 78',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            // Pas de validator : validatePhone retourne toujours null en V1.
          ),
        ],
      ),
    );
  }

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  ///
  /// Appelé par [TenantFormPage] lors du tap sur "Soumettre".
  bool validateAll() {
    setState(() {
      _firstNameTouched = true;
      _lastNameTouched = true;
      _emailTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }
}

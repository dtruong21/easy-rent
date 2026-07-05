import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/tenant_form_validators.dart';

/// Champs partagés du formulaire locataire.
///
/// Organisé en 3 sections :
/// 1. Identité (obligatoires + date de naissance, lieu de naissance, nationalité).
/// 2. Situation professionnelle (ExpansionTile optionnel) : profession, employeur,
///    revenus, adresse précédente.
/// 3. Garant / Caution (ExpansionTile optionnel) : nom, email, téléphone.
///
/// Utilisé dans [TenantFormPage] pour la création et l'édition.
/// Utiliser un [GlobalKey<TenantFormWidgetState>] pour appeler [validateAll].
class TenantForm extends StatefulWidget {
  const TenantForm({
    super.key,
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    // Champs identité étendus
    this.birthDate,
    required this.onBirthDateChanged,
    required this.birthPlaceController,
    required this.nationalityController,
    // Situation professionnelle
    required this.professionController,
    required this.employerController,
    required this.monthlyIncomeController,
    required this.previousAddressController,
    // Garant
    required this.guarantorNameController,
    required this.guarantorEmailController,
    required this.guarantorPhoneController,
    this.enabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final DateTime? birthDate;
  final ValueChanged<DateTime?> onBirthDateChanged;
  final TextEditingController birthPlaceController;
  final TextEditingController nationalityController;
  final TextEditingController professionController;
  final TextEditingController employerController;
  final TextEditingController monthlyIncomeController;
  final TextEditingController previousAddressController;
  final TextEditingController guarantorNameController;
  final TextEditingController guarantorEmailController;
  final TextEditingController guarantorPhoneController;
  final bool enabled;

  @override
  State<TenantForm> createState() => TenantFormWidgetState();
}

/// State public de [TenantForm] — exposé pour accès via [GlobalKey].
class TenantFormWidgetState extends State<TenantForm> {
  bool _firstNameTouched = false;
  bool _lastNameTouched = false;
  bool _emailTouched = false;
  bool _birthDateTouched = false;
  bool _guarantorEmailTouched = false;
  bool _monthlyIncomeTouched = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // Section 1 — Identité
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Identité'),
          const SizedBox(height: 12),

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

          // Téléphone (optionnel)
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
          ),
          const SizedBox(height: 16),

          // Date de naissance
          _BirthDateField(
            key: const Key('field_birth_date'),
            birthDate: widget.birthDate,
            onChanged: widget.onBirthDateChanged,
            enabled: widget.enabled,
            touched: _birthDateTouched,
            onTouched: () => setState(() => _birthDateTouched = true),
          ),
          const SizedBox(height: 16),

          // Lieu de naissance
          TextFormField(
            key: const Key('field_birth_place'),
            controller: widget.birthPlaceController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Lieu de naissance (optionnel)',
              hintText: 'Ex. : Paris',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // Nationalité
          TextFormField(
            key: const Key('field_nationality'),
            controller: widget.nationalityController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Nationalité (optionnel)',
              hintText: 'Ex. : Française',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),

          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Section 2 — Situation professionnelle (ExpansionTile)
          // ----------------------------------------------------------------
          _SituationProfessionnelleSection(
            professionController: widget.professionController,
            employerController: widget.employerController,
            monthlyIncomeController: widget.monthlyIncomeController,
            previousAddressController: widget.previousAddressController,
            enabled: widget.enabled,
            monthlyIncomeTouched: _monthlyIncomeTouched,
            onMonthlyIncomeTouched: () =>
                setState(() => _monthlyIncomeTouched = true),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------------------
          // Section 3 — Garant / Caution (ExpansionTile)
          // ----------------------------------------------------------------
          _GuarantorSection(
            guarantorNameController: widget.guarantorNameController,
            guarantorEmailController: widget.guarantorEmailController,
            guarantorPhoneController: widget.guarantorPhoneController,
            enabled: widget.enabled,
            guarantorEmailTouched: _guarantorEmailTouched,
            onGuarantorEmailTouched: () =>
                setState(() => _guarantorEmailTouched = true),
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
      _birthDateTouched = true;
      _guarantorEmailTouched = true;
      _monthlyIncomeTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Champ date de naissance (DatePicker)
// ---------------------------------------------------------------------------

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    super.key,
    required this.birthDate,
    required this.onChanged,
    required this.enabled,
    required this.touched,
    required this.onTouched,
  });

  final DateTime? birthDate;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;
  final bool touched;
  final VoidCallback onTouched;

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    // Calcul des bornes : min = 01/01/1900, max = aujourd'hui - 18 ans.
    final now = DateTime.now();
    final minDate = DateTime(1900);
    final maxDate = DateTime(now.year - 18, now.month, now.day);
    // Date initiale du picker : si déjà une valeur, l'utiliser ; sinon 30 ans en arrière.
    final initialDate =
        birthDate ?? DateTime(now.year - 30, now.month, now.day);

    final errorText = touched
        ? TenantFormValidators.validateBirthDate(birthDate)
        : null;

    return FormField<DateTime>(
      initialValue: birthDate,
      validator: (_) =>
          touched ? TenantFormValidators.validateBirthDate(birthDate) : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: enabled
                  ? () async {
                      onTouched();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate.isBefore(maxDate)
                            ? initialDate
                            : maxDate,
                        firstDate: minDate,
                        lastDate: maxDate,
                        locale: const Locale('fr', 'FR'),
                        helpText: 'Date de naissance',
                        fieldLabelText: 'Date de naissance',
                        fieldHintText: 'JJ/MM/AAAA',
                        cancelText: 'Annuler',
                        confirmText: 'Valider',
                      );
                      if (picked != null) {
                        onChanged(picked);
                      }
                    }
                  : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date de naissance (optionnel)',
                  hintText: 'JJ/MM/AAAA',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (birthDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Effacer',
                          onPressed: enabled
                              ? () {
                                  onChanged(null);
                                }
                              : null,
                        ),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
                isEmpty: birthDate == null,
                child: birthDate != null
                    ? Text(_formatDate(birthDate!))
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Section 2 — Situation professionnelle (ExpansionTile)
// ---------------------------------------------------------------------------

class _SituationProfessionnelleSection extends StatelessWidget {
  const _SituationProfessionnelleSection({
    required this.professionController,
    required this.employerController,
    required this.monthlyIncomeController,
    required this.previousAddressController,
    required this.enabled,
    required this.monthlyIncomeTouched,
    required this.onMonthlyIncomeTouched,
  });

  final TextEditingController professionController;
  final TextEditingController employerController;
  final TextEditingController monthlyIncomeController;
  final TextEditingController previousAddressController;
  final bool enabled;
  final bool monthlyIncomeTouched;
  final VoidCallback onMonthlyIncomeTouched;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_situation_pro'),
        title: const Text('Situation professionnelle (optionnel)'),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Profession
          TextFormField(
            key: const Key('field_profession'),
            controller: professionController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Profession',
              hintText: 'Ex. : Ingénieur',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // Employeur
          TextFormField(
            key: const Key('field_employer'),
            controller: employerController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Employeur',
              hintText: 'Ex. : Société XYZ',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // Revenus mensuels nets (en euros → stockés en centimes)
          TextFormField(
            key: const Key('field_monthly_income'),
            controller: monthlyIncomeController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Revenus mensuels nets',
              hintText: 'Ex. : 2500',
              helperText: 'en €',
              suffixText: '€',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onEditingComplete: () {
              onMonthlyIncomeTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!monthlyIncomeTouched) return null;
              if (v == null || v.trim().isEmpty) return null;
              final euros = int.tryParse(v.trim());
              if (euros == null) return 'Montant invalide';
              // Convertir en centimes pour valider la borne.
              return TenantFormValidators.validateMonthlyIncomeCents(
                euros * 100,
              );
            },
          ),
          const SizedBox(height: 16),

          // Adresse précédente
          TextFormField(
            key: const Key('field_previous_address'),
            controller: previousAddressController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Adresse précédente',
              hintText: 'Ex. : 5 rue des Fleurs, 75001 Paris',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 3 — Garant / Caution (ExpansionTile)
// ---------------------------------------------------------------------------

class _GuarantorSection extends StatelessWidget {
  const _GuarantorSection({
    required this.guarantorNameController,
    required this.guarantorEmailController,
    required this.guarantorPhoneController,
    required this.enabled,
    required this.guarantorEmailTouched,
    required this.onGuarantorEmailTouched,
  });

  final TextEditingController guarantorNameController;
  final TextEditingController guarantorEmailController;
  final TextEditingController guarantorPhoneController;
  final bool enabled;
  final bool guarantorEmailTouched;
  final VoidCallback onGuarantorEmailTouched;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_guarantor'),
        title: const Text('Garant / Caution (optionnel)'),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Nom du garant
          TextFormField(
            key: const Key('field_guarantor_name'),
            controller: guarantorNameController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Nom du garant',
              hintText: 'Ex. : Pierre Dupont',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // Email du garant
          TextFormField(
            key: const Key('field_guarantor_email'),
            controller: guarantorEmailController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Email du garant',
              hintText: 'Ex. : garant@email.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) {
              if (guarantorEmailTouched) {}
            },
            onEditingComplete: () {
              onGuarantorEmailTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!guarantorEmailTouched) return null;
              return TenantFormValidators.validateGuarantorEmail(v);
            },
          ),
          const SizedBox(height: 16),

          // Téléphone du garant
          TextFormField(
            key: const Key('field_guarantor_phone'),
            controller: guarantorPhoneController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Téléphone du garant',
              hintText: 'Ex. : 06 12 34 56 78',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }
}

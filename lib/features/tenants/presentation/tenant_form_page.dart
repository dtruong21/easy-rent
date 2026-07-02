import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../application/tenant_detail_provider.dart';
import '../application/tenant_form_controller.dart';
import '../domain/tenant.dart';
import '../domain/tenant_form_state.dart';
import 'widgets/tenant_form.dart';

final _log = Logger('TenantFormPage');

/// Formulaire partagé création / édition d'un locataire.
///
/// - [initial] == null → mode création (titre "Nouveau locataire").
/// - [initial] != null → mode édition (titre "Modifier le locataire", champs pré-remplis).
///
/// Sur succès : SnackBar toast + navigation vers la liste.
class TenantFormPage extends ConsumerStatefulWidget {
  const TenantFormPage({super.key, this.initial, this.popOnSuccess = false});

  /// Locataire à éditer, ou [null] pour une création.
  final Tenant? initial;

  /// Mode « picker » : la page a été pushée depuis un autre formulaire
  /// (ex. création de bail) — au succès on pop avec l'id du locataire créé
  /// pour que l'appelant le présélectionne, au lieu de naviguer vers la
  /// liste (flux « créer un bail sans repasser par le dashboard »).
  final bool popOnSuccess;

  @override
  ConsumerState<TenantFormPage> createState() => _TenantFormPageState();
}

class _TenantFormPageState extends ConsumerState<TenantFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<TenantFormWidgetState>();

  // Section 1 — Identité
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  DateTime? _birthDate;
  late final TextEditingController _birthPlaceCtrl;
  late final TextEditingController _nationalityCtrl;

  // Section 2 — Situation professionnelle
  late final TextEditingController _professionCtrl;
  late final TextEditingController _employerCtrl;
  late final TextEditingController _monthlyIncomeCtrl;
  late final TextEditingController _previousAddressCtrl;

  // Section 3 — Garant
  late final TextEditingController _guarantorNameCtrl;
  late final TextEditingController _guarantorEmailCtrl;
  late final TextEditingController _guarantorPhoneCtrl;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;

    _firstNameCtrl = TextEditingController(text: t?.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: t?.lastName ?? '');
    _emailCtrl = TextEditingController(text: t?.email ?? '');
    _phoneCtrl = TextEditingController(text: t?.phone ?? '');

    _birthDate = t?.birthDate;
    _birthPlaceCtrl = TextEditingController(text: t?.birthPlace ?? '');
    _nationalityCtrl = TextEditingController(text: t?.nationality ?? '');

    _professionCtrl = TextEditingController(text: t?.profession ?? '');
    _employerCtrl = TextEditingController(text: t?.employer ?? '');
    // Convertir centimes → euros pour l'affichage.
    _monthlyIncomeCtrl = TextEditingController(
      text: t?.monthlyIncomeCents != null
          ? '${t!.monthlyIncomeCents! ~/ 100}'
          : '',
    );
    _previousAddressCtrl = TextEditingController(
      text: t?.previousAddress ?? '',
    );

    _guarantorNameCtrl = TextEditingController(text: t?.guarantorName ?? '');
    _guarantorEmailCtrl = TextEditingController(text: t?.guarantorEmail ?? '');
    _guarantorPhoneCtrl = TextEditingController(text: t?.guarantorPhone ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _birthPlaceCtrl.dispose();
    _nationalityCtrl.dispose();
    _professionCtrl.dispose();
    _employerCtrl.dispose();
    _monthlyIncomeCtrl.dispose();
    _previousAddressCtrl.dispose();
    _guarantorNameCtrl.dispose();
    _guarantorEmailCtrl.dispose();
    _guarantorPhoneCtrl.dispose();
    super.dispose();
  }

  // Convertit la valeur texte euros → centimes (null si vide ou invalide).
  int? _parseMonthlyIncomeCents() {
    final text = _monthlyIncomeCtrl.text.trim();
    if (text.isEmpty) return null;
    final euros = int.tryParse(text);
    if (euros == null) return null;
    return euros * 100;
  }

  Future<void> _submit() async {
    // Valider tous les champs (marque tous comme "touchés").
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    await ref
        .read(tenantFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          firstName: _firstNameCtrl.text,
          lastName: _lastNameCtrl.text,
          email: _emailCtrl.text,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text,
          birthDate: _birthDate,
          birthPlace: _birthPlaceCtrl.text.trim().isEmpty
              ? null
              : _birthPlaceCtrl.text,
          nationality: _nationalityCtrl.text.trim().isEmpty
              ? null
              : _nationalityCtrl.text,
          profession: _professionCtrl.text.trim().isEmpty
              ? null
              : _professionCtrl.text,
          employer: _employerCtrl.text.trim().isEmpty
              ? null
              : _employerCtrl.text,
          monthlyIncomeCents: _parseMonthlyIncomeCents(),
          previousAddress: _previousAddressCtrl.text.trim().isEmpty
              ? null
              : _previousAddressCtrl.text,
          guarantorName: _guarantorNameCtrl.text.trim().isEmpty
              ? null
              : _guarantorNameCtrl.text,
          guarantorEmail: _guarantorEmailCtrl.text.trim().isEmpty
              ? null
              : _guarantorEmailCtrl.text,
          guarantorPhone: _guarantorPhoneCtrl.text.trim().isEmpty
              ? null
              : _guarantorPhoneCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;

    // Écouter les changements d'état pour les toasts et la navigation.
    ref.listen<TenantFormState>(tenantFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (tenant) {
          final msg = isCreating
              ? 'Locataire créé'
              : 'Modifications enregistrées';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          if (widget.popOnSuccess && context.canPop()) {
            context.pop(tenant.id);
          } else {
            context.go('/tenants');
          }
        },
        error: (_) {
          // L'erreur est affichée inline — pas besoin de toast supplémentaire.
          _log.warning('TenantFormPage error state');
        },
      );
    });

    final formState = ref.watch(tenantFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppAppBar(
        title: isCreating ? 'Nouveau locataire' : 'Modifier le locataire',
        fallbackRoute: '/tenants',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TenantForm(
              key: _formWidgetKey,
              formKey: _formKey,
              firstNameController: _firstNameCtrl,
              lastNameController: _lastNameCtrl,
              emailController: _emailCtrl,
              phoneController: _phoneCtrl,
              birthDate: _birthDate,
              onBirthDateChanged: (d) => setState(() => _birthDate = d),
              birthPlaceController: _birthPlaceCtrl,
              nationalityController: _nationalityCtrl,
              professionController: _professionCtrl,
              employerController: _employerCtrl,
              monthlyIncomeController: _monthlyIncomeCtrl,
              previousAddressController: _previousAddressCtrl,
              guarantorNameController: _guarantorNameCtrl,
              guarantorEmailController: _guarantorEmailCtrl,
              guarantorPhoneController: _guarantorPhoneCtrl,
              enabled: !isSubmitting,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('btn_submit_form'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isCreating ? 'Créer le locataire' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [TenantFormPage].
///
/// Route : `/tenants/:id/edit`
class TenantEditPage extends ConsumerWidget {
  const TenantEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTenant = ref.watch(tenantDetailProvider(id));

    return asyncTenant.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppAppBar(
          title: 'Modifier le locataire',
          fallbackRoute: '/tenants',
        ),
        body: Center(
          child: Text(
            'Locataire introuvable.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (tenant) => TenantFormPage(initial: tenant),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/surface_validator.dart';
import '../application/property_detail_provider.dart';
import '../application/property_form_controller.dart';
import '../domain/property.dart';
import '../domain/property_form_state.dart';
import '../domain/property_type.dart';
import 'widgets/property_form.dart';

final _log = Logger('PropertyFormPage');

/// Formulaire partagé création / édition d'un bien.
///
/// - [initial] == null → mode création (titre "Nouveau bien").
/// - [initial] != null → mode édition (titre "Modifier le bien", champs pré-remplis).
///
/// Sur succès : SnackBar toast + navigation vers la liste.
class PropertyFormPage extends ConsumerStatefulWidget {
  const PropertyFormPage({super.key, this.initial});

  /// Bien à éditer, ou [null] pour une création.
  final Property? initial;

  @override
  ConsumerState<PropertyFormPage> createState() => _PropertyFormPageState();
}

class _PropertyFormPageState extends ConsumerState<PropertyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<PropertyFormWidgetState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _surfaceCtrl;
  PropertyType? _selectedType;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _surfaceCtrl = TextEditingController(
      text: p?.surfaceM2 != null
          ? p!.surfaceM2!.toStringAsFixed(p.surfaceM2! % 1 == 0 ? 0 : 2)
          : '',
    );
    _selectedType = p?.type ?? PropertyType.appartement;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _surfaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Valider tous les champs (marque tous comme "touchés").
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    final surface = SurfaceValidator.parse(_surfaceCtrl.text);

    await ref
        .read(propertyFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          name: _nameCtrl.text,
          address: _addressCtrl.text,
          type: _selectedType!,
          surfaceM2: surface,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;

    // Écouter les changements d'état pour les toasts et la navigation.
    ref.listen<PropertyFormState>(propertyFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (property) {
          final msg = isCreating ? 'Bien créé' : 'Modifications enregistrées';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          context.go('/properties');
        },
        error: (_) {
          // L'erreur est affichée inline — pas besoin de toast supplémentaire.
          _log.warning('PropertyFormPage error state');
        },
      );
    });

    final formState = ref.watch(propertyFormControllerProvider);
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
        title: isCreating ? 'Nouveau bien' : 'Modifier le bien',
        fallbackRoute: '/properties',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PropertyForm(
              key: _formWidgetKey,
              formKey: _formKey,
              nameController: _nameCtrl,
              addressController: _addressCtrl,
              surfaceController: _surfaceCtrl,
              selectedType: _selectedType,
              onTypeChanged: (t) => setState(() => _selectedType = t),
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
                  : Text(isCreating ? 'Créer le bien' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [PropertyFormPage].
///
/// Route : `/properties/:id/edit`
class PropertyEditPage extends ConsumerWidget {
  const PropertyEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperty = ref.watch(propertyDetailProvider(id));

    return asyncProperty.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppAppBar(
          title: 'Modifier le bien',
          fallbackRoute: '/properties',
        ),
        body: Center(
          child: Text(
            'Bien introuvable.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (property) => PropertyFormPage(initial: property),
    );
  }
}

import 'package:flutter/material.dart';

import '../widgets/scenario_form_validators.dart';

/// Dialog de saisie du nom avant sauvegarde d'un scénario.
///
/// Retourne le nom saisi (String non vide) ou null si annulé.
///
/// Usage :
/// ```dart
/// final name = await showSaveScenarioDialog(context, initial: 'Mon scénario');
/// if (name != null) { /* save */ }
/// ```
Future<String?> showSaveScenarioDialog(
  BuildContext context, {
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SaveScenarioDialog(initial: initial),
  );
}

class _SaveScenarioDialog extends StatefulWidget {
  const _SaveScenarioDialog({this.initial});

  final String? initial;

  @override
  State<_SaveScenarioDialog> createState() => _SaveScenarioDialogState();
}

class _SaveScenarioDialogState extends State<_SaveScenarioDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nommer le scénario'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('save_scenario_name_field'),
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du scénario',
            hintText: 'Ex. : Appartement Lyon Centre',
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: ScenarioFormValidators.validateName,
          maxLength: 120,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('save_scenario_confirm'),
          onPressed: _submit,
          child: const Text('Sauvegarder'),
        ),
      ],
    );
  }
}

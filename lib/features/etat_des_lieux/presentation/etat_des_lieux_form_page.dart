import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/breakpoints.dart';
import '../../../core/ui/theme/app_spacing.dart';
import '../../../core/utils/french_date.dart';
import '../../receipts/data/web_share_service_bridge.dart';
import '../application/etat_des_lieux_form_controller.dart';
import '../data/etat_des_lieux_pdf_renderer.dart';
import '../domain/edl_default_template.dart';
import '../domain/edl_enums.dart';
import '../domain/etat_des_lieux.dart';
import 'edl_condition_l10n.dart';

final _log = Logger('EtatDesLieuxFormPage');

/// Signature de [renderEtatDesLieuxPdf] — indirection Riverpod pour permettre
/// aux tests d'injecter un renderer factice (le rendu réel embarque des
/// polices et est coûteux à exécuter dans une suite de tests widget, patron
/// `chargeRegularizationPdfRendererProvider` /
/// `charge_statement_finalize_controller.dart`).
typedef EtatDesLieuxPdfRenderer = Future<Uint8List> Function(EtatDesLieux edl);

final etatDesLieuxPdfRendererProvider = Provider<EtatDesLieuxPdfRenderer>(
  (ref) => renderEtatDesLieuxPdf,
);

/// Formulaire de création d'un état des lieux (FEAT-037).
///
/// Immuable une fois créé (pas de mode édition) : `landlordFullName` /
/// `landlordAddress` / `tenantFullName` / `propertyAddress` sont dérivés et
/// figés côté serveur (callable `createEtatDesLieux`) — ce formulaire ne les
/// demande donc jamais.
///
/// Sur succès : SnackBar toast, puis rendu + ouverture du PDF (patron
/// `open_receipt_pdf.dart`). Sur erreur : SnackBar i18n.
class EtatDesLieuxFormPage extends ConsumerStatefulWidget {
  const EtatDesLieuxFormPage({super.key, required this.leaseId});

  /// ID du bail parent.
  final String leaseId;

  @override
  ConsumerState<EtatDesLieuxFormPage> createState() =>
      _EtatDesLieuxFormPageState();
}

class _EtatDesLieuxFormPageState extends ConsumerState<EtatDesLieuxFormPage> {
  final _formKey = GlobalKey<FormState>();
  EtatDesLieuxType _type = EtatDesLieuxType.entree;
  DateTime _date = DateTime.now();
  late List<_RoomEdit> _rooms;

  final _waterCtrl = TextEditingController();
  final _electricityCtrl = TextEditingController();
  final _gasCtrl = TextEditingController();
  final _keysCtrl = TextEditingController(text: '2');
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rooms = defaultEdlRooms().map(_RoomEdit.fromRoom).toList();
  }

  @override
  void dispose() {
    _waterCtrl.dispose();
    _electricityCtrl.dispose();
    _gasCtrl.dispose();
    _keysCtrl.dispose();
    _commentCtrl.dispose();
    for (final room in _rooms) {
      room.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Mutations pièces/éléments
  // ---------------------------------------------------------------------

  void _addRoom() {
    setState(() {
      _rooms.add(_RoomEdit(name: '', elements: [_ElementEdit.blank()]));
    });
  }

  void _removeRoom(int roomIndex) {
    setState(() {
      _rooms.removeAt(roomIndex).dispose();
    });
  }

  void _addElement(int roomIndex) {
    setState(() {
      _rooms[roomIndex].elements.add(_ElementEdit.blank());
    });
  }

  void _removeElement(int roomIndex, int elementIndex) {
    setState(() {
      _rooms[roomIndex].elements.removeAt(elementIndex).dispose();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: context.l10n.edlDateLabel,
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  // ---------------------------------------------------------------------
  // Soumission
  // ---------------------------------------------------------------------

  Future<void> _submit() async {
    // Validation client : bloque les noms de pièce/élément vides avant l'appel
    // serveur (qui les refuserait avec un invalid-argument opaque). Met en
    // évidence le(s) champ(s) fautif(s) au lieu d'un message générique.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final water = _waterCtrl.text.trim();
    final electricity = _electricityCtrl.text.trim();
    final gas = _gasCtrl.text.trim();
    final comment = _commentCtrl.text.trim();

    await ref
        .read(etatDesLieuxFormControllerProvider.notifier)
        .submit(
          leaseId: widget.leaseId,
          type: _type,
          date: _date,
          rooms: _rooms.map((r) => r.toDomain()).toList(),
          meterReadings: EdlMeterReadings(
            waterIndex: water.isEmpty ? null : water,
            electricityIndex: electricity.isEmpty ? null : electricity,
            gasIndex: gas.isEmpty ? null : gas,
          ),
          keysCount: int.tryParse(_keysCtrl.text.trim()) ?? 0,
          generalComment: comment.isEmpty ? null : comment,
        );
  }

  /// Rend le PDF de l'état des lieux créé et l'ouvre (patron
  /// `open_receipt_pdf.dart`) : `blob:` sur web via [WebShareService], repli
  /// sur une URL `data:` ailleurs.
  Future<void> _openGeneratedPdf(EtatDesLieux edl) async {
    try {
      final bytes = await ref.read(etatDesLieuxPdfRendererProvider)(edl);

      final opened = await ref
          .read(webShareServiceProvider)
          .openPdfBytes(
            pdfBytes: bytes,
            filename: 'etat-des-lieux-${edl.id}.pdf',
          );
      if (opened) return;

      final uri = Uri.parse(
        'data:application/pdf;base64,${base64Encode(bytes)}',
      );
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.edlErrorOpenPdf)));
      }
    } catch (e, st) {
      _log.warning('Erreur ouverture PDF état des lieux', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.edlErrorOpenPdf),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  String _errorMessage(BuildContext context, EdlFormErrorReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      EdlFormErrorReason.profileIncomplete => l10n.edlErrorProfileIncomplete,
      EdlFormErrorReason.leaseNotOwned => l10n.edlErrorLeaseNotOwned,
      EdlFormErrorReason.generic => l10n.edlErrorGeneric,
    };
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();

    ref.listen<EdlFormState>(etatDesLieuxFormControllerProvider, (_, next) {
      if (!context.mounted) return;
      if (next is EdlFormSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.edlCreatedSnackbar),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        unawaited(_openGeneratedPdf(next.edl));
      } else if (next is EdlFormError) {
        _log.warning('EtatDesLieuxFormPage error state: ${next.reason}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage(context, next.reason)),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
    });

    final isSubmitting =
        ref.watch(etatDesLieuxFormControllerProvider) is EdlFormSubmitting;

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.edlFormTitle,
        fallbackRoute: '/leases/${widget.leaseId}',
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTypeAndDateCard(context, spacing),
              SizedBox(height: spacing.xl),
              _buildRoomsSection(context, spacing),
              SizedBox(height: spacing.xl),
              _buildMetersSection(context, spacing),
              SizedBox(height: spacing.xl),
              _buildKeysAndCommentSection(context, spacing),
              SizedBox(height: spacing.xxl),
              FilledButton(
                key: const Key('edl_generate_button'),
                onPressed: isSubmitting ? null : _submit,
                child: isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.edlGenerate),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeAndDateCard(BuildContext context, AppSpacing spacing) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.edlTypeLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: spacing.sm),
            SegmentedButton<EtatDesLieuxType>(
              key: const Key('edl_type_segmented_button'),
              segments: [
                ButtonSegment(
                  value: EtatDesLieuxType.entree,
                  label: Text(l10n.edlTypeEntree),
                ),
                ButtonSegment(
                  value: EtatDesLieuxType.sortie,
                  label: Text(l10n.edlTypeSortie),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => _type = selection.first);
                }
              },
              showSelectedIcon: false,
            ),
            SizedBox(height: spacing.lg),
            InkWell(
              key: const Key('edl_date_field'),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.edlDateLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                ),
                child: Text(FrenchDate.format(_date)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsSection(BuildContext context, AppSpacing spacing) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.edlSectionRooms,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: spacing.sm),
        for (var i = 0; i < _rooms.length; i++) ...[
          _buildRoomCard(context, spacing, i),
          SizedBox(height: spacing.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('edl_add_room_button'),
            onPressed: _addRoom,
            icon: const Icon(Icons.add),
            label: Text(l10n.edlAddRoom),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomCard(
    BuildContext context,
    AppSpacing spacing,
    int roomIndex,
  ) {
    final l10n = context.l10n;
    final room = _rooms[roomIndex];
    return Card(
      key: Key('edl_room_card_$roomIndex'),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('edl_room_name_field_$roomIndex'),
                    controller: room.nameCtrl,
                    style: Theme.of(context).textTheme.titleSmall,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? l10n.validationRequired
                        : null,
                    decoration: InputDecoration(
                      labelText: l10n.edlRoomNameLabel,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('edl_remove_room_button_$roomIndex'),
                  tooltip: l10n.edlRemoveRoomTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeRoom(roomIndex),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            for (var j = 0; j < room.elements.length; j++) ...[
              _buildElementRow(context, spacing, roomIndex, j),
              SizedBox(height: spacing.sm),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('edl_add_element_button_$roomIndex'),
                onPressed: () => _addElement(roomIndex),
                icon: const Icon(Icons.add),
                label: Text(l10n.edlAddElement),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementRow(
    BuildContext context,
    AppSpacing spacing,
    int roomIndex,
    int elementIndex,
  ) {
    final l10n = context.l10n;
    final element = _rooms[roomIndex].elements[elementIndex];

    final nameField = TextFormField(
      key: Key('edl_element_name_field_${roomIndex}_$elementIndex'),
      controller: element.nameCtrl,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) =>
          (v ?? '').trim().isEmpty ? l10n.validationRequired : null,
      decoration: InputDecoration(
        labelText: l10n.edlElementNameLabel,
        isDense: true,
      ),
    );

    final conditionDropdown = DropdownButton<EdlCondition>(
      key: Key('edl_element_condition_dropdown_${roomIndex}_$elementIndex'),
      value: element.condition,
      items: EdlCondition.values
          .map((c) => DropdownMenuItem(value: c, child: Text(c.label(context))))
          .toList(),
      onChanged: (c) {
        if (c != null) setState(() => element.condition = c);
      },
    );

    final commentField = TextFormField(
      key: Key('edl_element_comment_field_${roomIndex}_$elementIndex'),
      controller: element.commentCtrl,
      decoration: InputDecoration(
        labelText: l10n.edlElementCommentLabel,
        isDense: true,
      ),
    );

    final removeButton = IconButton(
      key: Key('edl_remove_element_button_${roomIndex}_$elementIndex'),
      tooltip: l10n.edlRemoveElementTooltip,
      icon: const Icon(Icons.close, size: 18),
      onPressed: () => _removeElement(roomIndex, elementIndex),
    );

    if (context.isMobile) {
      return Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: nameField),
                removeButton,
              ],
            ),
            SizedBox(height: spacing.xs),
            conditionDropdown,
            SizedBox(height: spacing.xs),
            commentField,
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: nameField),
          SizedBox(width: spacing.sm),
          conditionDropdown,
          SizedBox(width: spacing.sm),
          Expanded(flex: 3, child: commentField),
          removeButton,
        ],
      ),
    );
  }

  Widget _buildMetersSection(BuildContext context, AppSpacing spacing) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.edlSectionMeters,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: spacing.sm),
        Wrap(
          spacing: spacing.md,
          runSpacing: spacing.md,
          children: [
            SizedBox(
              width: 200,
              child: TextFormField(
                key: const Key('edl_water_field'),
                controller: _waterCtrl,
                decoration: InputDecoration(labelText: l10n.edlMeterWater),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextFormField(
                key: const Key('edl_electricity_field'),
                controller: _electricityCtrl,
                decoration: InputDecoration(
                  labelText: l10n.edlMeterElectricity,
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextFormField(
                key: const Key('edl_gas_field'),
                controller: _gasCtrl,
                decoration: InputDecoration(labelText: l10n.edlMeterGas),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeysAndCommentSection(BuildContext context, AppSpacing spacing) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 200,
          child: TextFormField(
            key: const Key('edl_keys_count_field'),
            controller: _keysCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l10n.edlKeysCount),
          ),
        ),
        SizedBox(height: spacing.lg),
        TextFormField(
          key: const Key('edl_general_comment_field'),
          controller: _commentCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.edlGeneralComment,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// État local d'édition (pièces/éléments) — tient les TextEditingController le
// temps de la saisie ; converti en modèle domaine ([EdlRoom]/[EdlElement])
// uniquement à la soumission.
// ---------------------------------------------------------------------------

class _ElementEdit {
  _ElementEdit({required String name, required this.condition, String? comment})
    : nameCtrl = TextEditingController(text: name),
      commentCtrl = TextEditingController(text: comment ?? '');

  factory _ElementEdit.blank() =>
      _ElementEdit(name: '', condition: EdlCondition.bon);

  final TextEditingController nameCtrl;
  final TextEditingController commentCtrl;
  EdlCondition condition;

  EdlElement toDomain() => EdlElement(
    name: nameCtrl.text.trim(),
    condition: condition,
    comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
  );

  void dispose() {
    nameCtrl.dispose();
    commentCtrl.dispose();
  }
}

class _RoomEdit {
  _RoomEdit({required String name, required this.elements})
    : nameCtrl = TextEditingController(text: name);

  factory _RoomEdit.fromRoom(EdlRoom room) => _RoomEdit(
    name: room.name,
    elements: room.elements
        .map(
          (e) => _ElementEdit(
            name: e.name,
            condition: e.condition,
            comment: e.comment,
          ),
        )
        .toList(),
  );

  final TextEditingController nameCtrl;
  final List<_ElementEdit> elements;

  EdlRoom toDomain() => EdlRoom(
    name: nameCtrl.text.trim(),
    elements: elements.map((e) => e.toDomain()).toList(),
  );

  void dispose() {
    nameCtrl.dispose();
    for (final element in elements) {
      element.dispose();
    }
  }
}

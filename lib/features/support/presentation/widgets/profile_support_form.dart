import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/support_controller.dart';
import '../../domain/support_request_state.dart';
import '../../domain/support_submit_error.dart';
import '../support_submit_error_l10n.dart';

/// Formulaire inline « Nous contacter » (sujet + message).
///
/// Le controller reste pur (sans dépendance à [PackageInfo]) : la version
/// de l'app et l'environnement sont lus ici, dans le widget, et passés en
/// paramètres à [SupportController.submit].
class ProfileSupportForm extends ConsumerStatefulWidget {
  const ProfileSupportForm({super.key});

  @override
  ConsumerState<ProfileSupportForm> createState() => _ProfileSupportFormState();
}

class _ProfileSupportFormState extends ConsumerState<ProfileSupportForm> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _subjectController.addListener(_rebuild);
    _messageController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _subjectController.removeListener(_rebuild);
    _messageController.removeListener(_rebuild);
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _subjectController.text.trim().isNotEmpty &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final asyncInfo = ref.read(appInfoProvider);
    final appVersion = asyncInfo.maybeWhen(
      data: (info) => '${info.version}+${info.buildNumber}',
      orElse: () => 'inconnue',
    );
    await ref
        .read(supportControllerProvider.notifier)
        .submit(
          subject: _subjectController.text,
          message: _messageController.text,
          appVersion: appVersion,
          appEnv: Env.appEnv,
        );
  }

  void _clearFields() {
    _subjectController.clear();
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(supportControllerProvider);
    final l10n = context.l10n;
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (code) => SupportSubmitError.fromCode(code).message(context),
      orElse: () => null,
    );
    final theme = Theme.of(context);

    ref.listen<SupportRequestState>(supportControllerProvider, (_, next) {
      next.maybeWhen(
        success: () {
          _clearFields();
          ref.read(supportControllerProvider.notifier).reset();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.supportFormSuccessSnackbar),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
        },
        orElse: () {},
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          key: const Key('field_support_subject'),
          controller: _subjectController,
          enabled: !isSubmitting,
          maxLength: kSupportSubjectMaxLength,
          decoration: InputDecoration(
            labelText: l10n.supportFormSubjectLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('field_support_message'),
          controller: _messageController,
          enabled: !isSubmitting,
          maxLines: 5,
          maxLength: kSupportMessageMaxLength,
          decoration: InputDecoration(
            labelText: l10n.supportFormMessageLabel,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('btn_support_submit'),
          onPressed: (_canSubmit && !isSubmitting) ? _submit : null,
          child: isSubmitting
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : Text(l10n.supportFormSubmitButton),
        ),
      ],
    );
  }
}

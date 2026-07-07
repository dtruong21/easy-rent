import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../application/landlord_profile_provider.dart';
import '../application/profile_form_controller.dart';
import '../domain/landlord_profile.dart';
import '../domain/profile_form_state.dart';
import 'profile_form_error_reason_l10n.dart';
import 'widgets/profile_form.dart';

final _log = Logger('ProfileDetailsPage');

/// Page `/profile/details` — identité du bailleur (loi 1989 art. 21).
///
/// Formulaire : email en lecture seule (identifiant d'auth non modifiable),
/// nom complet et adresse obligatoires (requis pour générer des quittances),
/// téléphone facultatif.
///
/// Le pré-remplissage est chargé depuis [landlordProfileProvider]
/// (AsyncNotifier). Les états loading/error du chargement initial sont
/// gérés explicitement.
class ProfileDetailsPage extends ConsumerStatefulWidget {
  const ProfileDetailsPage({super.key});

  @override
  ConsumerState<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends ConsumerState<ProfileDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<ProfileFormWidgetState>();
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  /// Indique si les contrôleurs de texte ont été initialisés avec les données
  /// du profil chargé. Évite une réinitialisation à chaque rebuild.
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Pré-remplit les contrôleurs de texte avec le profil chargé.
  ///
  /// Appelé une seule fois lors de la réception du profil initial.
  void _initFromProfile(LandlordProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _fullNameCtrl.text = profile.fullName ?? '';
    _phoneCtrl.text = profile.phone ?? '';
    _addressCtrl.text = profile.address ?? '';
  }

  Future<void> _submit() async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    await ref
        .read(profileFormControllerProvider.notifier)
        .submit(
          fullName: _fullNameCtrl.text.trim().isEmpty
              ? null
              : _fullNameCtrl.text,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text,
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Écouter les changements d'état pour les toasts.
    ref.listen<ProfileFormState>(profileFormControllerProvider, (_, next) {
      if (!context.mounted) return;
      next.whenOrNull(
        success: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.profileDetailsUpdatedSnackbar),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        },
        error: (_) {
          _log.warning('ProfileDetailsPage error state');
        },
      );
    });

    final formState = ref.watch(profileFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (reason) => reason.message(context),
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.profileDetailsTitle,
        fallbackRoute: '/profile',
      ),
      body: _buildBody(isSubmitting: isSubmitting, errorMessage: errorMessage),
    );
  }

  Widget _buildBody({
    required bool isSubmitting,
    required String? errorMessage,
  }) {
    final asyncProfile = ref.watch(landlordProfileProvider);
    final l10n = context.l10n;

    return asyncProfile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.profileDetailsLoadError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(landlordProfileProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.commonRetry),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        _initFromProfile(profile);
        return _buildForm(
          profile: profile,
          isSubmitting: isSubmitting,
          errorMessage: errorMessage,
        );
      },
    );
  }

  Widget _buildForm({
    required LandlordProfile profile,
    required bool isSubmitting,
    required String? errorMessage,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Email en lecture seule — identifiant d'auth non modifiable.
              _EmailReadOnlyField(email: profile.email),
              const SizedBox(height: 24),

              ProfileForm(
                key: _formWidgetKey,
                formKey: _formKey,
                fullNameController: _fullNameCtrl,
                phoneController: _phoneCtrl,
                addressController: _addressCtrl,
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
                key: const Key('btn_save_profile'),
                onPressed: isSubmitting ? null : _submit,
                child: isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.commonSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Champ email en lecture seule.
///
/// Extrait en sous-widget pour garder [_ProfileDetailsPageState] sous la
/// limite de 200 lignes.
class _EmailReadOnlyField extends StatelessWidget {
  const _EmailReadOnlyField({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      key: const Key('field_email_readonly'),
      initialValue: email,
      readOnly: true,
      decoration: InputDecoration(
        labelText: l10n.profileDetailsEmailLabel,
        helperText: l10n.profileDetailsEmailHelper,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.lock_outline),
      ),
    );
  }
}

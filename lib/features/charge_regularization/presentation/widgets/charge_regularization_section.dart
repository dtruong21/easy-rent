import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../leases/domain/lease.dart';
import 'charge_regularization_dialog.dart';

/// Section "Charges" de [LeaseDetailPage] (FEAT-029 V1.2, FEAT-042).
///
/// Gate légal : la régularisation annuelle des charges (art. 23 loi du 6
/// juillet 1989) ne s'applique qu'aux baux dont le **mode de charges
/// effectif** est `provisions` (cf. `Lease.canRegularizeCharges`, FEAT-042).
/// Le critère n'est PAS le type de bail — un bail meublé ou étudiant en
/// provisions est éligible, un bail (quel que soit son type) au forfait ne
/// l'est jamais.
///
/// - Mode provisions : bouton d'action "Régularisation annuelle des charges".
/// - Mode forfait : pas de bouton, message informatif sobre — évite une
///   fausse impression de conformité sur un cas où la loi ne l'exige pas.
class ChargeRegularizationSection extends StatelessWidget {
  const ChargeRegularizationSection({
    super.key,
    required this.lease,
    required this.landlordFullName,
    required this.landlordAddress,
    required this.tenantFullName,
    required this.tenantFirstName,
    required this.propertyAddress,
    this.tenantEmail,
  });

  /// Bien rattaché au bail — transmis au dialog pour charger les dépenses
  /// récupérables (FEAT-041c). Lu directement depuis [lease.propertyId],
  /// pas de paramètre séparé nécessaire.
  final Lease lease;
  final String landlordFullName;
  final String landlordAddress;
  final String tenantFullName;
  final String tenantFirstName;
  final String propertyAddress;
  final String? tenantEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRegularize = lease.canRegularizeCharges;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chargeRegularizationSectionTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (canRegularize)
              OutlinedButton.icon(
                key: const Key('btn_charge_regularization'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(context.l10n.chargeRegularizationOpenDialogButton),
                onPressed: () => _openDialog(context),
              )
            else
              Text(
                key: const Key('text_charge_regularization_not_applicable'),
                context.l10n.chargeRegularizationForfaitNotApplicable,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ChargeRegularizationDialog(
        leaseId: lease.id,
        propertyId: lease.propertyId,
        landlordFullName: landlordFullName,
        landlordAddress: landlordAddress,
        tenantFullName: tenantFullName,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        tenantEmail: tenantEmail,
      ),
    );
  }
}

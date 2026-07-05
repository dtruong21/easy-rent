import 'package:flutter/material.dart';

import '../../../leases/domain/lease.dart';
import '../../../leases/domain/lease_type.dart';
import 'charge_regularization_dialog.dart';

/// Section "Charges" de [LeaseDetailPage] (FEAT-029 V1.2).
///
/// Gate légal : la régularisation annuelle des charges (art. 23 loi du 6
/// juillet 1989) ne s'applique qu'aux baux nus. Pour les autres types
/// (meublé, mobilité, étudiant), le forfait de charges est libératoire — pas
/// de régularisation légale. Décision de scope V1 : uniquement
/// `LeaseType.unfurnished` (cf. `docs/backlog/029-charges-regularisation.md`,
/// § « Régime meublé vs nu »).
///
/// - Bail nu : bouton d'action "Régularisation annuelle des charges".
/// - Autres types : pas de bouton, message informatif sobre — évite une
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
    final isUnfurnished = lease.leaseType == LeaseType.unfurnished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Régularisation des charges',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (isUnfurnished)
              OutlinedButton.icon(
                key: const Key('btn_charge_regularization'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Régularisation annuelle des charges'),
                onPressed: () => _openDialog(context),
              )
            else
              Text(
                key: const Key('text_charge_regularization_not_applicable'),
                'Le forfait de charges ne donne pas lieu à régularisation '
                'légale pour ce type de bail.',
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

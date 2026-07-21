import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/subscription_tier.dart';
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
///
/// Gate PRO (FEAT-044, matrice free/Pro 2026-07-20) : la régularisation est une
/// fonction « comptable » avancée réservée au palier `paid`. **Précédence
/// volontaire** : le gate LÉGAL passe en premier — sur un bail au forfait on
/// affiche le message d'inapplicabilité, PAS un upsell Pro (il serait trompeur
/// de vendre une fonction que la loi n'autorise pas ici). L'upsell n'apparaît
/// donc que sur un bail réellement éligible.
///
/// Le calcul et le PDF sont 100 % côté client : ce gate est une restriction
/// produit, pas une frontière de sécurité (aucune ressource serveur à protéger,
/// contrairement au quota documents qui, lui, est enforced en Cloud Function).
class ChargeRegularizationSection extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canRegularize = lease.canRegularizeCharges;
    // Fail-closed pendant le chargement du tier (même convention que
    // `scenarioLimitForTierProvider`) : on n'affiche pas le bouton par défaut,
    // ce qui évite un flash « action dispo » avant de le retirer.
    final isPaid =
        ref.watch(landlordTierProvider).valueOrNull?.tier ==
        SubscriptionTier.paid;

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
            if (canRegularize && isPaid)
              OutlinedButton.icon(
                key: const Key('btn_charge_regularization'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(context.l10n.chargeRegularizationOpenDialogButton),
                onPressed: () => _openDialog(context),
              )
            else if (canRegularize)
              // Bail éligible mais palier free/anonymous → état verrouillé Pro.
              Row(
                key: const Key('text_charge_regularization_pro_only'),
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.chargeRegularizationProOnly,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
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

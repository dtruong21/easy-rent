import 'package:flutter/material.dart';

/// Carte d'offre unique de la page `/pro` (FEAT-056 PR-6) — purement
/// présentationnelle : aucun appel réseau, aucune lecture Riverpod. Le CTA
/// ([cta]) est composé par l'appelant ([ProPricingPage]), qui seul connaît
/// l'état d'abonnement courant et peut décider entre S'abonner / Offre
/// actuelle / Passer à… / Revenir à… / Bientôt disponible.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.title,
    required this.tagline,
    required this.bullets,
    required this.cta,
    this.priceLabel,
    this.priceIndicativeSuffix,
    this.recommended = false,
    this.recommendedLabel,
    this.badge,
  });

  final String title;
  final String tagline;
  final List<String> bullets;

  /// Widget de CTA déjà résolu par l'appelant (bouton, texte désactivé, bloc
  /// « bientôt disponible »...).
  final Widget cta;

  /// `null` pour la carte Gratuit (pas de prix affiché).
  final String? priceLabel;

  /// Suffixe affiché après [priceLabel] quand le prix est indicatif (ex.
  /// « (indicatif) », déjà résolu/traduit par l'appelant) — palier pas
  /// encore ouvert à la vente (FEAT-056 §2.3-b). `null`/vide = prix ferme,
  /// aucun suffixe.
  final String? priceIndicativeSuffix;

  /// Palier mis en avant (issu de la table de config, jamais codé en dur) —
  /// bordure + badge [recommendedLabel].
  final bool recommended;
  final String? recommendedLabel;

  /// Badge additionnel (ex. « Bientôt disponible ») affiché à côté du titre.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: recommended ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: recommended
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recommended && recommendedLabel != null) ...[
              _Chip(
                text: recommendedLabel!,
                color: theme.colorScheme.primaryContainer,
                onColor: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?badge,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tagline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (priceLabel != null)
              _PriceRow(
                priceLabel: priceLabel!,
                indicativeSuffix: priceIndicativeSuffix,
              ),
            const SizedBox(height: 16),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(bullet, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            cta,
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.priceLabel, this.indicativeSuffix});

  final String priceLabel;
  final String? indicativeSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Colonne plutôt que ligne : à 4 cartes par rangée (desktop, ~260px de
    // contenu utile), « 24,99 € » + « (indicatif) » côte à côte déborde —
    // le suffixe passe donc sous le prix plutôt qu'à sa droite.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          priceLabel,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (indicativeSuffix != null && indicativeSuffix!.isNotEmpty)
          Text(
            indicativeSuffix!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, required this.onColor});

  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: onColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

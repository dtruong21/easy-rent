import 'package:flutter/material.dart';

import '../../domain/property.dart';
import '../../domain/property_type.dart';

/// Card cliquable représentant un bien dans la liste.
///
/// Affiche : nom, type traduit, adresse tronquée, surface (si renseignée).
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property, required this.onTap});

  final Property property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  _iconForType(property.type),
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      property.type.labelFr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      property.address,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (property.surfaceM2 != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2)} m²',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(PropertyType type) => switch (type) {
    PropertyType.appartement => Icons.apartment,
    PropertyType.maison => Icons.house,
    PropertyType.studio => Icons.single_bed,
    PropertyType.autre => Icons.home_work,
  };
}

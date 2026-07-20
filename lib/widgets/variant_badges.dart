import 'package:flutter/material.dart';

import '../utils/color_names.dart';

/// Small pill badges showing a size/color variant, if any. Renders nothing
/// when both [size] and [color] are blank.
class VariantBadges extends StatelessWidget {
  const VariantBadges({super.key, required this.size, required this.color, this.dense = false});

  final String size;
  final String color;

  /// Slightly smaller/tighter styling for use in compact tiles.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (size.isEmpty && color.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (size.isNotEmpty)
          _Badge(
            dense: dense,
            label: size,
            icon: Icons.straighten,
            theme: theme,
          ),
        if (color.isNotEmpty)
          _Badge(
            dense: dense,
            label: color,
            theme: theme,
            swatch: colorFromName(color) ?? theme.colorScheme.surfaceContainerHighest,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.theme,
    this.icon,
    this.swatch,
    this.dense = false,
  });

  final String label;
  final ThemeData theme;
  final IconData? icon;
  final Color? swatch;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null)
            Container(
              width: dense ? 9 : 11,
              height: dense ? 9 : 11,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: swatch,
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              ),
            )
          else if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: dense ? 11 : 13, color: theme.colorScheme.onSurfaceVariant),
            ),
          Text(
            label,
            style: (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

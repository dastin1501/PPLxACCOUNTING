import 'package:flutter/material.dart';

/// Best-effort mapping from a free-typed color name (e.g. "Grey", "Navy
/// Blue") to an actual [Color] swatch, for showing a small preview dot next
/// to a stock item's color attribute. Returns null when the name isn't
/// recognized, so callers can fall back to a neutral placeholder.
Color? colorFromName(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;

  for (final entry in _colorNames.entries) {
    if (key == entry.key || key.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

const _colorNames = <String, Color>{
  'black': Colors.black,
  'white': Colors.white,
  'grey': Colors.grey,
  'gray': Colors.grey,
  'red': Colors.red,
  'maroon': Color(0xFF800000),
  'pink': Colors.pink,
  'magenta': Colors.pinkAccent,
  'orange': Colors.orange,
  'yellow': Colors.yellow,
  'gold': Color(0xFFFFD700),
  'brown': Colors.brown,
  'beige': Color(0xFFF5F5DC),
  'tan': Color(0xFFD2B48C),
  'cream': Color(0xFFFFFDD0),
  'green': Colors.green,
  'olive': Color(0xFF808000),
  'lime': Colors.lime,
  'teal': Colors.teal,
  'cyan': Colors.cyan,
  'blue': Colors.blue,
  'navy': Color(0xFF000080),
  'indigo': Colors.indigo,
  'purple': Colors.purple,
  'violet': Color(0xFF8F00FF),
  'lavender': Color(0xFFE6E6FA),
  'silver': Color(0xFFC0C0C0),
};

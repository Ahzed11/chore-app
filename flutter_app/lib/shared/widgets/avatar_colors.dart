import 'package:flutter/material.dart';

/// Shared avatar color palette, keyed off a display name's first character.
///
/// Used to be defined (with drifting palettes — some screens were missing
/// the teal entry) separately in `chore_card.dart`, `member_tile.dart`,
/// `household_management_screen.dart`, and `leaderboard_screen.dart`
/// (TASK-065). Consolidated here so the same person always gets the same
/// avatar color everywhere in the app.
const List<Color> avatarColorPalette = [
  Color(0xFF14B8A6),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFF22C55E),
  Color(0xFFF472B6),
  Color(0xFFF97316),
  Color(0xFF0D9488),
];

/// Deterministic avatar background color for [name] (typically a display
/// name). Empty names fall back to the first palette color.
Color avatarColorForName(String name) {
  if (name.isEmpty) return avatarColorPalette[0];
  return avatarColorPalette[name.codeUnitAt(0) % avatarColorPalette.length];
}

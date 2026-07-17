import 'package:flutter/material.dart';

/// Drop-in replacement for a bare `GestureDetector` tap target (TASK-066).
///
/// Bare `GestureDetector`s have no semantics — TalkBack/VoiceOver announce
/// nothing meaningful and there's no visual tap feedback. This wraps [child]
/// in `Semantics(button: true, label: ...)` plus a ripple-producing `InkWell`
/// so keyboard/screen-reader users get an announced, focusable control while
/// the visual appearance (the wrapped [child] itself) is unchanged.
///
/// [naturalSize] + [minTapSize] together enlarge the tappable/hit-test area
/// up to the 48dp minimum *without* growing the space this widget occupies
/// in its parent layout (e.g. a `Row` of same-sized icon buttons): pass the
/// child's actual visual size as [naturalSize] (e.g. `40` for a 40×40
/// `Container`) and the desired minimum as [minTapSize] (`48`). The extra
/// hit area simply overflows the natural-sized layout slot, centered on it —
/// the same technique used for the chore-complete status circle in
/// `chore_card.dart`.
class AccessibleTap extends StatelessWidget {
  const AccessibleTap({
    super.key,
    required this.onTap,
    required this.label,
    required this.child,
    this.onLongPress,
    this.borderRadius,
    this.customBorder,
    this.selected,
    this.naturalSize,
    this.minTapSize,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Announced to assistive technology (e.g. "Back", "Mark chore done").
  final String label;

  final Widget child;

  /// Matches the visual shape for the ripple clip — pass the same
  /// `BorderRadius` the wrapped `Container`/`Card` uses.
  final BorderRadius? borderRadius;

  /// Alternative to [borderRadius] for circular tap targets.
  final ShapeBorder? customBorder;

  /// For toggle-like controls (e.g. a selected tab/segment), reported to
  /// assistive tech via `Semantics.selected`.
  final bool? selected;

  /// [child]'s actual (square) visual size — required together with
  /// [minTapSize] to enlarge the hit area without affecting layout.
  final double? naturalSize;

  /// Minimum tap-target size (both dimensions), e.g. `48`. No effect unless
  /// [naturalSize] is also set and smaller than this.
  final double? minTapSize;

  @override
  Widget build(BuildContext context) {
    Widget tappable = Semantics(
      button: true,
      label: label,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        shape: customBorder,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: customBorder == null ? borderRadius : null,
          customBorder: customBorder,
          excludeFromSemantics: true,
          child: child,
        ),
      ),
    );

    final natural = naturalSize;
    final minTap = minTapSize;
    if (natural != null && minTap != null && minTap > natural) {
      tappable = SizedBox(
        width: natural,
        height: natural,
        child: OverflowBox(
          minWidth: minTap,
          minHeight: minTap,
          maxWidth: minTap,
          maxHeight: minTap,
          child: tappable,
        ),
      );
    }

    return tappable;
  }
}

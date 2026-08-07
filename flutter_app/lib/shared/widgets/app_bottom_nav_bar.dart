import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';

/// The four-destination bottom navigation bar shared by every household tab
/// screen (All Chores / My Chores / Leaderboard / Groceries).
///
/// Each tab screen used to carry its own private copy of this bar, and the
/// copies drifted apart — the "All Chores" icon was `format_list_bulleted`
/// on one tab and `checklist` on the others, and the Leaderboard icon was a
/// trophy (`emoji_events_rounded`) on one tab and a bar chart
/// (`leaderboard_rounded`) elsewhere. This widget is the single source of
/// truth for the bar's icons, labels, order and navigation, so it renders
/// identically on every tab.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.householdId,
    required this.currentIndex,
  });

  /// Household whose tab routes this bar navigates between.
  final String householdId;

  /// Index of the tab currently on screen (0..3); the corresponding
  /// destination is highlighted and tapping it is a no-op.
  final int currentIndex;

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    final route = switch (index) {
      0 => AppRoutes.choreList,
      1 => AppRoutes.myChores,
      2 => AppRoutes.leaderboard,
      3 => AppRoutes.groceryList,
      _ => null,
    };
    if (route != null) {
      context.goNamed(route, pathParameters: {'householdId': householdId});
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      key: const Key('bottom_nav_bar'),
      currentIndex: currentIndex,
      onTap: (index) => _onTap(context, index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.checklist_rounded),
          label: 'All Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'My Chores',
        ),
        BottomNavigationBarItem(
          // Trophy — kept consistent across all tabs (the old chores-tab
          // copy used this; the other three used the bar-chart icon).
          icon: Icon(Icons.emoji_events_rounded),
          label: 'Leaderboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart_rounded),
          label: 'Groceries',
        ),
      ],
    );
  }
}

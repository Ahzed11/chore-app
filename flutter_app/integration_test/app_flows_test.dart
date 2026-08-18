import 'package:chore_app/core/auth/auth_state.dart';
import 'package:chore_app/core/config/server_config_storage.dart';
import 'package:chore_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ---------------------------------------------------------------------------
// End-to-end journey (TASK-110, Layer 2) — runs the REAL app against a LIVE
// backend on the Linux desktop device.
//
// Run:
//   cd flutter_app
//   flutter test integration_test/app_flows_test.dart -d linux \
//     --dart-define=API_BASE_URL=http://localhost:8000
//
// Headless: wrap with xvfb-run -a and a dbus session with an unlocked
// gnome-keyring (flutter_secure_storage requires one on Linux):
//   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
//     printf "\n" | gnome-keyring-daemon --unlock --components=secrets
//     flutter test integration_test/app_flows_test.dart -d linux \
//       --dart-define=API_BASE_URL=http://localhost:8000
//   '
//
// Full journey: register → create household → create chore → copy from
// existing task (assert the 4 fields prefill) → dismiss → complete →
// leaderboard points → logout.
// ---------------------------------------------------------------------------

/// Pumps until [finder] matches or [timeout] elapses. Real network I/O does
/// not schedule frames, so `pumpAndSettle` alone can return before a request
/// lands — every network-triggering action must be followed by a [waitFor].
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for $finder${reason == null ? '' : ' ($reason)'}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Unique per run so re-runs against the same DB never collide.
  final runId = DateTime.now().millisecondsSinceEpoch;
  final email = 'e2e_$runId@example.com';
  const displayName = 'E2E Tester';
  const password = 'E2E_Passw0rd!';
  final householdName = 'E2E Home $runId';

  testWidgets('register → household → chore → copy → dismiss → complete → '
      'leaderboard → logout', (tester) async {
    // --- Deterministic start: wipe persisted server URL + session -----------
    await ServerConfigStorage.clearUrl();
    await AuthStorage.clearToken();
    await AuthStorage.clearRefreshToken();

    app.main();
    await waitFor(
      tester,
      find.byKey(const Key('server_setup_url_field')),
      reason: 'first-run server setup',
    );

    // --- Point the app at the live backend ---------------------------------
    await tester.enterText(
      find.byKey(const Key('server_setup_url_field')),
      'http://localhost:8000',
    );
    await tester.tap(find.byKey(const Key('server_setup_test_button')));
    await waitFor(
      tester,
      find.byKey(const Key('login_email_field')),
      reason: 'server setup succeeded → login screen',
    );

    // --- Register -----------------------------------------------------------
    await tester.tap(find.byKey(const Key('login_register_link')));
    await waitFor(
      tester,
      find.byKey(const Key('register_display_name_field')),
      reason: 'register screen',
    );
    await tester.enterText(
      find.byKey(const Key('register_display_name_field')),
      displayName,
    );
    await tester.enterText(
      find.byKey(const Key('register_email_field')),
      email,
    );
    await tester.enterText(
      find.byKey(const Key('register_password_field')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('register_confirm_password_field')),
      password,
    );
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await waitFor(
      tester,
      find.byKey(const Key('create_household_fab')),
      reason: 'registration landed on the households dashboard',
    );

    // --- Create a household ------------------------------------------------
    await tester.tap(find.byKey(const Key('create_household_fab')));
    await waitFor(
      tester,
      find.byKey(const Key('create_household_name_field')),
      reason: 'create-household sheet',
    );
    await tester.enterText(
      find.byKey(const Key('create_household_name_field')),
      householdName,
    );
    await tester.tap(find.byKey(const Key('create_household_submit_button')));
    await waitFor(
      tester,
      find.text(householdName),
      reason: 'household card appears on the dashboard',
    );

    // --- Enter the household (All Chores tab) ------------------------------
    final householdCard = find.text(householdName);
    await waitFor(tester, householdCard, reason: 'household card appears');
    await tester.ensureVisible(householdCard);
    await tester.tap(householdCard);
    await waitFor(
      tester,
      find.byKey(const Key('add_chore_fab')),
      reason: 'chore list screen',
    );

    // --- Create chore #1 ----------------------------------------------------
    await tester.tap(find.byKey(const Key('add_chore_fab')));
    await waitFor(
      tester,
      find.byKey(const Key('title_field')),
      reason: 'create-chore form',
    );
    await tester.enterText(
      find.byKey(const Key('title_field')),
      'Wash the dishes',
    );
    await tester.enterText(
      find.byKey(const Key('description_field')),
      'Dishes from dinner',
    );

    // Category dropdown → Kitchen
    await tester.ensureVisible(find.byKey(const Key('category_dropdown')));
    await tester.tap(find.byKey(const Key('category_dropdown')));
    await waitFor(tester, find.text('Kitchen').last);
    await tester.tap(find.text('Kitchen').last);
    await tester.pumpAndSettle();

    // Due date → today via the date picker
    await tester.ensureVisible(find.byKey(const Key('due_date_field')));
    await tester.tap(find.byKey(const Key('due_date_field')));
    await waitFor(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The submit button sits below the fold on a 721px-tall desktop window.
    await tester.ensureVisible(find.byKey(const Key('submit_button')));
    await tester.tap(find.byKey(const Key('submit_button')));
    await waitFor(
      tester,
      find.text('Wash the dishes'),
      reason: 'chore #1 appears in the list',
    );

    // --- Create chore #2 BY COPYING chore #1 (TASK-108/109) ----------------
    await tester.tap(find.byKey(const Key('add_chore_fab')));
    await waitFor(
      tester,
      find.byKey(const Key('copy_from_task_button')),
      reason: 'create form with copy control',
    );
    await tester.ensureVisible(
      find.byKey(const Key('copy_from_task_button')),
    );
    await tester.tap(find.byKey(const Key('copy_from_task_button')));
    await waitFor(
      tester,
      find.byType(BottomSheet),
      reason: 'copy-from-existing-task sheet opens',
    );

    // Select the "Wash the dishes" row inside the sheet.
    final sheetRow = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Wash the dishes'),
    );
    await waitFor(tester, sheetRow, reason: 'template row in copy sheet');
    await tester.tap(sheetRow.first);
    await tester.pumpAndSettle();

    // The 4 fields must be prefilled from the template.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('title_field')))
          .controller
          ?.text,
      'Wash the dishes',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('description_field')))
          .controller
          ?.text,
      'Dishes from dinner',
    );
    expect(find.text('Kitchen'), findsOneWidget, reason: 'category copied');
    expect(
      find.text('Medium'),
      findsOneWidget,
      reason: 'effort level copied (default Medium)',
    );

    // Give it a distinct title, pick a due date, and submit.
    await tester.enterText(
      find.byKey(const Key('title_field')),
      'Wash the dishes (copied)',
    );
    await tester.ensureVisible(find.byKey(const Key('due_date_field')));
    await tester.tap(find.byKey(const Key('due_date_field')));
    await waitFor(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('submit_button')));
    await tester.tap(find.byKey(const Key('submit_button')));
    await waitFor(
      tester,
      find.text('Wash the dishes (copied)'),
      reason: 'chore #2 (copied) appears in the list',
    );

    // TASK-111: newest-created chore must be on top — the copied chore was
    // created after the original, so it renders above it.
    final copiedY = tester
        .getTopLeft(find.text('Wash the dishes (copied)'))
        .dy;
    final originalY = tester.getTopLeft(find.text('Wash the dishes')).dy;
    expect(
      copiedY,
      lessThan(originalY),
      reason: 'newest-created chore appears at the top of the list',
    );

    // --- Dismiss chore #1 (TASK-104: long-press → Dismiss) ----------------
    final firstChore = find.text('Wash the dishes');
    await waitFor(tester, firstChore, reason: 'chore #1 in the list');
    await tester.ensureVisible(firstChore);
    await tester.longPress(firstChore);
    await waitFor(
      tester,
      find.byKey(const Key('dismiss_menu_item')),
      reason: 'long-press context menu',
    );
    await tester.tap(find.byKey(const Key('dismiss_menu_item')));
    await waitFor(
      tester,
      find.byKey(const Key('dismiss_sheet_title')),
      reason: 'dismiss confirmation sheet',
    );
    await tester.tap(find.byKey(const Key('dismiss_confirm_button')));
    await waitFor(
      tester,
      find.text('No points'),
      reason: 'chore #1 dismissed (card shows the No-points pill)',
    );

    // --- Complete chore #2 (admin "mark done for assignee") ----------------
    final secondChore = find.text('Wash the dishes (copied)');
    await waitFor(tester, secondChore, reason: 'chore #2 in the list');
    await tester.ensureVisible(secondChore);
    await tester.longPress(secondChore);
    await waitFor(
      tester,
      find.byKey(const Key('mark_done_for_menu_item')),
      reason: 'long-press context menu (admin)',
    );
    await tester.tap(find.byKey(const Key('mark_done_for_menu_item')));
    await waitFor(
      tester,
      find.byKey(const Key('complete_sheet_title')),
      reason: 'complete confirmation sheet',
    );
    await tester.tap(find.byKey(const Key('confirm_done_button')));
    await waitFor(
      tester,
      find.text('25'),
      reason: 'chore #2 complete (card shows the 25-points pill)',
    );

    // --- Leaderboard: completed chore's points are credited ----------------
    // (Medium = 25 pts; the dismissed chore awards nothing.)
    await tester.tap(find.text('Leaderboard'));
    await waitFor(
      tester,
      find.text(displayName),
      reason: 'leaderboard lists the member',
    );
    await waitFor(
      tester,
      find.text('25 pts'),
      reason: '25 points for the completed chore (leaderboard "N pts" row)',
    );

    // --- Logout -------------------------------------------------------------
    // Back to the All Chores tab (the leaderboard has no header back button),
    // then to the dashboard via the chore list header back button
    // (AccessibleTap exposes a Semantics label, not a Tooltip).
    await tester.tap(find.text('All Chores'));
    await waitFor(
      tester,
      find.byKey(const Key('add_chore_fab')),
      reason: 'back on the All Chores tab',
    );
    await tester.tap(find.bySemanticsLabel('Back to households'));
    await waitFor(
      tester,
      find.byKey(const Key('logout_button')),
      reason: 'household dashboard',
    );
    await tester.tap(find.byKey(const Key('logout_button')));
    await waitFor(
      tester,
      find.byKey(const Key('login_email_field')),
      reason: 'logged out → login screen',
    );
  });
}

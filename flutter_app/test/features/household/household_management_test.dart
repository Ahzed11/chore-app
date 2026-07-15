import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/features/household/screens/household_management_screen.dart';
import 'package:chore_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Sample data
// ---------------------------------------------------------------------------

HouseholdModel _household({
  String id = 'h1',
  String name = 'Test Home',
  String role = 'admin',
  int memberCount = 3,
}) {
  return HouseholdModel(
    id: id,
    name: name,
    role: role,
    memberCount: memberCount,
    createdAt: DateTime(2025, 1, 1),
  );
}

MemberModel _member({
  String userId = 'u1',
  String displayName = 'Alice',
  String role = 'admin',
}) {
  return MemberModel(
    userId: userId,
    displayName: displayName,
    role: role,
    joinedAt: DateTime(2025, 3, 1),
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _FakeHouseholdsNotifier extends HouseholdsNotifier {
  _FakeHouseholdsNotifier(this._households);

  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;

  @override
  Future<void> updateHouseholdName(
      String householdId, String newName) async {}

  @override
  Future<void> leaveHousehold(String householdId) async {}
}

class _FakeHouseholdsNotifierSoleAdmin extends HouseholdsNotifier {
  _FakeHouseholdsNotifierSoleAdmin(this._households);

  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;

  @override
  Future<void> leaveHousehold(String householdId) async {
    throw const SoleAdminException(
      'You are the sole admin. Promote another member first.',
    );
  }
}

class _FakeMembersNotifier extends MembersNotifier {
  _FakeMembersNotifier(this._members);

  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;

  @override
  Future<void> changeRole(String userId, String newRole) async {}

  @override
  Future<void> removeMember(String userId) async {}
}

class _FakeMembersNotifierSoleAdmin extends MembersNotifier {
  _FakeMembersNotifierSoleAdmin(this._members);

  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;

  @override
  Future<void> removeMember(String userId) async {
    throw const SoleAdminException('Cannot remove the sole admin.');
  }
}

// ---------------------------------------------------------------------------
// Widget builder helpers
// ---------------------------------------------------------------------------

/// Creates a minimal GoRouter that hosts the management screen at
/// `/households/:householdId/manage`.  This is required because
/// `_confirmLeave` calls `GoRouter.of(context)` after `await`.
GoRouter _testRouter({
  required String householdId,
  required Widget Function(String) screenBuilder,
}) {
  return GoRouter(
    initialLocation: '/households/$householdId/manage',
    routes: [
      GoRoute(
        path: '/households/:householdId/manage',
        builder: (context, state) {
          final id = state.pathParameters['householdId']!;
          return screenBuilder(id);
        },
      ),
      GoRoute(
        path: '/households',
        builder: (context, state) =>
            const Scaffold(body: Text('Households')),
      ),
      GoRoute(
        path: '/households/:householdId/invite',
        builder: (context, state) =>
            const Scaffold(body: Text('Invite')),
      ),
    ],
  );
}

Widget _buildScreen({
  required List<HouseholdModel> households,
  required List<MemberModel> members,
  String householdId = 'h1',
  String? currentUserId = 'u99', // different from any member by default
  HouseholdsNotifier Function()? householdsNotifierFactory,
  MembersNotifier Function()? membersNotifierFactory,
}) {
  final router = _testRouter(
    householdId: householdId,
    screenBuilder: (id) => HouseholdManagementScreen(householdId: id),
  );

  return ProviderScope(
    overrides: [
      householdsNotifierProvider.overrideWith(
        householdsNotifierFactory ??
            () => _FakeHouseholdsNotifier(households),
      ),
      // Family providers are overridden at the family level, not per-argument.
      membersNotifierProvider.overrideWith(
        membersNotifierFactory ?? () => _FakeMembersNotifier(members),
      ),
      currentUserIdProvider.overrideWithValue(currentUserId),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

/// Pumps [widget] with an enlarged viewport so the whole scrollable content
/// of the management screen (including the danger-zone "Leave household"
/// button at the bottom) is laid out on screen and hit-testable without
/// having to scroll it into view first.
Future<void> _pumpScreen(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(widget);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  const householdId = 'h1';

  group('HouseholdManagementScreen', () {
    // -----------------------------------------------------------------------
    // Member list rendering
    // -----------------------------------------------------------------------

    testWidgets('member list renders correctly with role badges',
        (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u1', displayName: 'Alice', role: 'admin'),
        _member(userId: 'u2', displayName: 'Bob', role: 'member'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Admin badge for Alice
      expect(find.byKey(const Key('role_badge_admin_u1')), findsOneWidget);
      // Member badge for Bob
      expect(find.byKey(const Key('role_badge_member_u2')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Popup menu — admin member shows "Change to Member"
    // -----------------------------------------------------------------------

    testWidgets('admin tile shows "Change to Member" in popup menu',
        (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u1', displayName: 'Alice', role: 'admin'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      // Open the popup menu for Alice.
      await tester.tap(find.byKey(const Key('member_menu_u1')));
      await tester.pumpAndSettle();

      expect(find.text('Change to Member'), findsOneWidget);
      expect(find.text('Remove from household'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Popup menu — regular member shows "Change to Admin"
    // -----------------------------------------------------------------------

    testWidgets('member tile shows "Change to Admin" in popup menu',
        (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u2', displayName: 'Bob', role: 'member'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member_menu_u2')));
      await tester.pumpAndSettle();

      expect(find.text('Change to Admin'), findsOneWidget);
      expect(find.text('Remove from household'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Remove triggers confirmation dialog
    // -----------------------------------------------------------------------

    testWidgets('remove option triggers confirmation dialog', (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u2', displayName: 'Bob', role: 'member'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      // Open popup menu.
      await tester.tap(find.byKey(const Key('member_menu_u2')));
      await tester.pumpAndSettle();

      // Tap "Remove from household".
      await tester.tap(find.text('Remove from household'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear.
      expect(find.byKey(const Key('remove_confirm_button')), findsOneWidget);
      expect(find.byKey(const Key('remove_cancel_button')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Sole admin remove shows error snackbar (not dialog)
    // -----------------------------------------------------------------------

    testWidgets(
        'sole admin remove error shows snackbar "Cannot remove the sole admin."',
        (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u1', displayName: 'Alice', role: 'admin'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(
          households: households,
          members: members,
          membersNotifierFactory: () =>
              _FakeMembersNotifierSoleAdmin(members),
        ),
      );
      await tester.pumpAndSettle();

      // Open popup menu for Alice.
      await tester.tap(find.byKey(const Key('member_menu_u1')));
      await tester.pumpAndSettle();

      // Tap "Remove from household".
      await tester.tap(find.text('Remove from household'));
      await tester.pumpAndSettle();

      // Confirm the removal.
      await tester.tap(find.byKey(const Key('remove_confirm_button')));
      await tester.pumpAndSettle();

      // Error snackbar should appear.
      expect(find.byKey(const Key('sole_admin_snackbar')), findsOneWidget);
      expect(
        find.text('Cannot remove the sole admin.'),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Edit household name — the redesign replaced the modal dialog with an
    // inline edit field inside the hero card.
    // -----------------------------------------------------------------------

    testWidgets('editing household name shows a field pre-filled with the current name',
        (tester) async {
      final households = [_household(id: householdId, name: 'My Home')];
      final members = <MemberModel>[];

      await _pumpScreen(tester,
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      // Before editing, the plain name tile is shown (no dialog needed).
      expect(find.byKey(const Key('household_name_tile')), findsOneWidget);
      expect(find.text('My Home'), findsOneWidget);

      // Tap the edit icon to switch the hero card into inline-edit mode.
      await tester.tap(find.byKey(const Key('edit_name_button')));
      await tester.pumpAndSettle();

      // The text field should be pre-filled with the current name.
      final textField = tester.widget<TextField>(
        find.byKey(const Key('household_name_field')),
      );
      expect(textField.controller?.text, 'My Home');
    });

    // -----------------------------------------------------------------------
    // Leave household shows confirmation dialog
    // -----------------------------------------------------------------------

    testWidgets('leave household shows confirmation dialog', (tester) async {
      final households = [_household(id: householdId)];
      final members = <MemberModel>[];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      // Tap the "Leave household" button.
      await tester.tap(find.byKey(const Key('leave_household_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leave_dialog')), findsOneWidget);
      expect(find.byKey(const Key('leave_confirm_button')), findsOneWidget);
      expect(find.byKey(const Key('leave_cancel_button')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Leave household — sole admin shows error dialog
    // -----------------------------------------------------------------------

    testWidgets(
        'sole admin leave shows error dialog with correct message',
        (tester) async {
      final households = [_household(id: householdId)];
      final members = <MemberModel>[];

      await _pumpScreen(tester, 
        _buildScreen(
          households: households,
          members: members,
          householdsNotifierFactory: () =>
              _FakeHouseholdsNotifierSoleAdmin(households),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Leave household".
      await tester.tap(find.byKey(const Key('leave_household_button')));
      await tester.pumpAndSettle();

      // Confirm in the first dialog.
      await tester.tap(find.byKey(const Key('leave_confirm_button')));
      await tester.pumpAndSettle();

      // Error dialog should be shown.
      expect(
        find.byKey(const Key('sole_admin_error_dialog')),
        findsOneWidget,
      );
      expect(
        find.text(
            'You are the sole admin. Promote another member first.'),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Invite button is present
    // -----------------------------------------------------------------------

    testWidgets('invite button is present', (tester) async {
      final households = [_household(id: householdId)];
      final members = <MemberModel>[];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invite_tile')), findsOneWidget);
      expect(find.text('Invite a housemate'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Current user's own row has no popup menu
    // -----------------------------------------------------------------------

    testWidgets("current user's own row has no popup menu", (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'me', displayName: 'Me', role: 'admin'),
        _member(userId: 'u2', displayName: 'Other', role: 'member'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(
          households: households,
          members: members,
          currentUserId: 'me',
        ),
      );
      await tester.pumpAndSettle();

      // The current user's tile should have no popup menu.
      expect(find.byKey(const Key('member_menu_me')), findsNothing);
      // The other member's tile should have a popup menu.
      expect(find.byKey(const Key('member_menu_u2')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Admin role badge has amber background
    // -----------------------------------------------------------------------

    testWidgets('Admin role badge has amber background', (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u1', displayName: 'Alice', role: 'admin'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      final badgeFinder = find.byKey(const Key('role_badge_admin_u1'));
      expect(badgeFinder, findsOneWidget);

      final container = tester.widget<Container>(badgeFinder);
      final decoration = container.decoration! as BoxDecoration;
      final bg = decoration.color!;
      final r = (bg.r * 255.0).round().clamp(0, 255);
      final g = (bg.g * 255.0).round().clamp(0, 255);
      final b = (bg.b * 255.0).round().clamp(0, 255);
      // Amber 100 has high red + green, low blue.
      expect(r, greaterThan(b));
      expect(g, greaterThan(b));
    });

    // -----------------------------------------------------------------------
    // Member role badge has grey background
    // -----------------------------------------------------------------------

    testWidgets('Member role badge has grey background', (tester) async {
      final households = [_household(id: householdId)];
      final members = [
        _member(userId: 'u2', displayName: 'Bob', role: 'member'),
      ];

      await _pumpScreen(tester, 
        _buildScreen(households: households, members: members),
      );
      await tester.pumpAndSettle();

      final badgeFinder = find.byKey(const Key('role_badge_member_u2'));
      expect(badgeFinder, findsOneWidget);

      final container = tester.widget<Container>(badgeFinder);
      final decoration = container.decoration! as BoxDecoration;
      final bg = decoration.color!;
      final r = (bg.r * 255.0).round().clamp(0, 255);
      final g = (bg.g * 255.0).round().clamp(0, 255);
      final b = (bg.b * 255.0).round().clamp(0, 255);
      // Grey shade 200 has similar R, G, B values.
      final diff = (r - g).abs() + (g - b).abs();
      expect(diff, lessThan(20));
    });
  });
}

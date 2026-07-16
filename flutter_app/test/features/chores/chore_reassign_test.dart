import 'package:chore_app/features/auth/providers/current_user_provider.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/chore_list_screen.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants & data helpers
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';
const _kCurrentUserId = 'user-1';

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String status = 'pending',
  String? assigneeId = 'user-2',
  String? assigneeName = 'Bob',
  DateTime? dueDate,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: _kHouseholdId,
    assigneeId: assigneeId,
    assigneeName: assigneeName,
    assignedManually: false,
    dueDate: dueDate ?? DateTime(2027, 6, 25),
    status: status,
    title: title,
    category: 'kitchen',
    effortLevel: 'easy',
    choreType: 'recurring',
  );
}

HouseholdModel _household({String role = 'admin'}) {
  return HouseholdModel(
    id: _kHouseholdId,
    name: 'Test Home',
    role: role,
    memberCount: 2,
    createdAt: DateTime(2025, 1, 1),
  );
}

MemberModel _member({
  String userId = 'user-2',
  String displayName = 'Bob',
  String role = 'member',
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

class _TrackingChoresNotifier extends ChoresNotifier {
  _TrackingChoresNotifier(this._chores);
  final List<ChoreModel> _chores;

  final List<({String instanceId, String assigneeId})> reassignCalls = [];

  @override
  Future<List<ChoreModel>> build(String arg) async => _chores;

  @override
  Future<void> reassignChore(String instanceId, String assigneeId) async {
    reassignCalls.add((instanceId: instanceId, assigneeId: assigneeId));
  }

  @override
  Future<void> refresh() async {}
}

class _ThrowingChoresNotifier extends _TrackingChoresNotifier {
  _ThrowingChoresNotifier(super.chores, this._statusCode);
  final int _statusCode;

  @override
  Future<void> reassignChore(String instanceId, String assigneeId) async {
    final requestOptions = RequestOptions(path: '/x');
    throw DioException(
      requestOptions: requestOptions,
      response: Response(
        requestOptions: requestOptions,
        statusCode: _statusCode,
      ),
    );
  }
}

class _FakeMembersNotifier extends MembersNotifier {
  _FakeMembersNotifier(this._members);
  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;
}

class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);
  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

// ---------------------------------------------------------------------------
// Widget builder helper
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required ChoresNotifier Function() choresNotifier,
  List<HouseholdModel>? households,
  List<MemberModel>? members,
}) {
  return ProviderScope(
    overrides: [
      choresNotifierProvider.overrideWith(choresNotifier),
      householdsNotifierProvider.overrideWith(
        () => _DataHouseholdsNotifier(households ?? [_household()]),
      ),
      membersNotifierProvider.overrideWith(
        () => _FakeMembersNotifier(
          members ??
              [
                _member(userId: 'user-1', displayName: 'Alice', role: 'admin'),
                _member(userId: 'user-2', displayName: 'Bob'),
              ],
        ),
      ),
      currentUserProvider.overrideWith(
        (ref) async =>
            const UserProfile(id: _kCurrentUserId, displayName: 'Alice'),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ChoreListScreen(householdId: _kHouseholdId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Chore reassignment (TASK-052)', () {
    testWidgets(
        'admin long-press on a pending chore shows "Reassign chore" action',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reassign_chore_menu_item')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delete_series_menu_item')), findsOneWidget);
    });

    testWidgets('overdue chore also shows the reassign action',
        (tester) async {
      final notifier = _TrackingChoresNotifier([
        _chore(status: 'overdue', dueDate: DateTime(2025, 1, 1)),
      ]);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reassign_chore_menu_item')),
        findsOneWidget,
      );
    });

    testWidgets('completed chore does not show the reassign action',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore(status: 'complete')]);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      // Admin menu opens (delete is available) but reassign is hidden.
      expect(find.byKey(const Key('delete_series_menu_item')), findsOneWidget);
      expect(find.byKey(const Key('reassign_chore_menu_item')), findsNothing);
    });

    testWidgets('non-admin long-press shows no admin menu at all',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildScreen(
        choresNotifier: () => notifier,
        households: [_household(role: 'member')],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reassign_chore_menu_item')), findsNothing);
      expect(find.byKey(const Key('delete_series_menu_item')), findsNothing);
    });

    testWidgets(
        'selecting a member calls reassignChore with the instance and member ids',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reassign_chore_menu_item')));
      await tester.pumpAndSettle();

      // Member picker lists both household members.
      expect(find.byKey(const Key('reassign_member_user-1')), findsOneWidget);
      expect(find.byKey(const Key('reassign_member_user-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reassign_member_user-1')));
      await tester.pumpAndSettle();

      expect(notifier.reassignCalls, hasLength(1));
      expect(notifier.reassignCalls.single.instanceId, 'c1');
      expect(notifier.reassignCalls.single.assigneeId, 'user-1');

      // Success snackbar.
      expect(find.text('Chore reassigned.'), findsOneWidget);
    });

    testWidgets('current assignee is marked with a check in the picker',
        (tester) async {
      final notifier = _TrackingChoresNotifier([_chore()]);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassign_chore_menu_item')));
      await tester.pumpAndSettle();

      // The chore is assigned to user-2 (Bob) — his row carries the check.
      final bobRow = tester.widget<ListTile>(
        find.byKey(const Key('reassign_member_user-2')),
      );
      expect(bobRow.trailing, isNotNull);

      final aliceRow = tester.widget<ListTile>(
        find.byKey(const Key('reassign_member_user-1')),
      );
      expect(aliceRow.trailing, isNull);
    });

    testWidgets('409 error shows a friendly conflict message', (tester) async {
      final notifier = _ThrowingChoresNotifier([_chore()], 409);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassign_chore_menu_item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassign_member_user-1')));
      await tester.pumpAndSettle();

      expect(
        find.text('This chore can no longer be reassigned.'),
        findsOneWidget,
      );
    });

    testWidgets('403 error shows a friendly permission message',
        (tester) async {
      final notifier = _ThrowingChoresNotifier([_chore()], 403);
      await tester.pumpWidget(_buildScreen(choresNotifier: () => notifier));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('chore_card_c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassign_chore_menu_item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassign_member_user-1')));
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to reassign chores.'),
        findsOneWidget,
      );
    });
  });
}

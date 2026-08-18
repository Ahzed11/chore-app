import 'package:chore_app/features/auth/providers/current_user_provider.dart';
import 'package:chore_app/features/chores/models/chore_model.dart';
import 'package:chore_app/features/chores/models/chore_template.dart';
import 'package:chore_app/features/chores/providers/chore_templates_provider.dart';
import 'package:chore_app/features/chores/providers/chores_provider.dart';
import 'package:chore_app/features/chores/screens/chore_list_screen.dart';
import 'package:chore_app/features/chores/screens/create_chore_screen.dart';
import 'package:chore_app/features/chores/screens/my_chores_screen.dart';
import 'package:chore_app/features/groceries/models/grocery_item_model.dart';
import 'package:chore_app/features/groceries/providers/groceries_provider.dart';
import 'package:chore_app/features/groceries/screens/grocery_list_screen.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/models/member_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/providers/members_provider.dart';
import 'package:chore_app/features/household/screens/household_dashboard_screen.dart';
import 'package:chore_app/features/leaderboard/models/leaderboard_model.dart';
import 'package:chore_app/features/leaderboard/providers/leaderboard_provider.dart';
import 'package:chore_app/features/leaderboard/screens/leaderboard_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Layout / overflow smoke sweep (TASK-110, Layer 1)
//
// Pumps every major screen with empty / one / many data variants and asserts
// `tester.takeException()` is null after `pumpAndSettle()`. Any RenderFlex
// overflow, unbounded-height exception, or other uncaught error here is a REAL
// bug to fix — this sweep exists to make that class of bug impossible to ship
// (the copy-from-existing-task sheet below is exactly such a bug, TASK-109).
//
// To add a screen: copy an existing group, override the providers the screen
// watches (see the per-screen test files under test/features/ for the exact
// provider sets), and iterate the data variants you care about.
// ---------------------------------------------------------------------------

const _kHouseholdId = 'hh-1';
const _kUserId = 'user-1';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ChoreModel _chore({
  String id = 'c1',
  String title = 'Wash dishes',
  String status = 'pending',
  String category = 'kitchen',
  String effortLevel = 'easy',
  DateTime? dueDate,
  DateTime? createdAt,
}) {
  return ChoreModel(
    id: id,
    definitionId: 'def-$id',
    householdId: _kHouseholdId,
    assigneeId: _kUserId,
    assigneeName: 'Test User',
    assignedManually: false,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    dueDate: dueDate ?? DateTime(2026, 6, 25),
    status: status,
    completedAt: status == 'complete' || status == 'dismissed'
        ? DateTime(2026, 8, 1)
        : null,
    pointsAwarded: status == 'complete' ? 5 : null,
    title: title,
    description: 'Do the thing',
    category: category,
    effortLevel: effortLevel,
    choreType: 'recurring',
  );
}

HouseholdModel _household({String id = _kHouseholdId, String role = 'admin'}) {
  return HouseholdModel(
    id: id,
    name: 'Test Home',
    role: role,
    memberCount: 2,
    createdAt: DateTime(2025, 1, 1),
  );
}

MemberModel _member(String id, String name) {
  return MemberModel(
    userId: id,
    displayName: name,
    role: 'member',
    joinedAt: DateTime(2025, 1, 1),
  );
}

ChoreTemplate _template(int i) {
  return ChoreTemplate(
    id: 't$i',
    title: 'Template task number $i',
    description: 'Description for template $i',
    category: 'kitchen',
    effortLevel: 'medium',
  );
}

GroceryItemModel _grocery(String id, String name, {bool purchased = false}) {
  return GroceryItemModel(
    id: id,
    householdId: _kHouseholdId,
    addedById: _kUserId,
    addedByName: 'Test User',
    name: name,
    quantity: '1',
    notes: null,
    isPurchased: purchased,
    purchasedById: purchased ? _kUserId : null,
    purchasedByName: purchased ? 'Test User' : null,
    purchasedAt: purchased ? DateTime(2026, 8, 5) : null,
    createdAt: DateTime(2026, 8, 1),
  );
}

LeaderboardResult _leaderboard(int entryCount) {
  return LeaderboardResult(
    scope: LeaderboardScope.allTime,
    entries: [
      for (var i = 1; i <= entryCount; i++)
        LeaderboardEntry(
          rank: i,
          userId: 'u$i',
          displayName: 'Member $i',
          points: 100 - i,
          choresCompleted: 10 - i,
        ),
    ],
    requestingUserRank: 1,
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers (data variants only — loading/error states are covered by
// the per-screen unit tests; this sweep is about layout with content)
// ---------------------------------------------------------------------------

class _DataChoresNotifier extends ChoresNotifier {
  _DataChoresNotifier(this._chores);
  final List<ChoreModel> _chores;

  @override
  Future<List<ChoreModel>> build(String arg) async => _chores;
}

class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);
  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

class _DataMembersNotifier extends MembersNotifier {
  _DataMembersNotifier(this._members);
  final List<MemberModel> _members;

  @override
  Future<List<MemberModel>> build(String arg) async => _members;
}

class _DataTemplatesNotifier extends ChoreTemplatesNotifier {
  _DataTemplatesNotifier(this._templates);
  final List<ChoreTemplate> _templates;

  @override
  Future<List<ChoreTemplate>> build(String arg) async => _templates;

  @override
  Future<void> hideTemplate(String definitionId) async {}
}

class _DataGroceriesNotifier extends GroceriesNotifier {
  _DataGroceriesNotifier(this._items);
  final List<GroceryItemModel> _items;

  @override
  Future<List<GroceryItemModel>> build(String arg) async => _items;
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps [widget] and asserts the whole subtree settles without an uncaught
/// exception (overflow, unbounded constraints, layout crash).
Future<void> _pumpAndExpectClean(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Realistic phone portrait surface (logical 390x844 @3x) — the size where
/// bottom-sheet overflow bugs actually bite (the TASK-109 repro).
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Small phone surface (logical 320x568 @2x) — narrow enough to expose
/// horizontal RenderFlex overflows (the TASK-112 dropdown repro).
void _narrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 2, 568 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) {
  return MaterialApp(theme: AppTheme.lightTheme, home: home);
}

// ---------------------------------------------------------------------------
// Sweep
// ---------------------------------------------------------------------------

void main() {
  group('layout smoke sweep', () {
    // -----------------------------------------------------------------------
    // Household dashboard (households list)
    // -----------------------------------------------------------------------
    group('HouseholdDashboardScreen', () {
      testWidgets('empty, one, and many households lay out cleanly',
          (tester) async {
        for (final households in [
          <HouseholdModel>[],
          [_household()],
          [
            for (var i = 1; i <= 8; i++)
              _household(id: 'hh-$i', role: i == 1 ? 'admin' : 'member'),
          ],
        ]) {
          await _pumpAndExpectClean(
            tester,
            ProviderScope(
              overrides: [
                householdsNotifierProvider.overrideWith(
                  () => _DataHouseholdsNotifier(households),
                ),
              ],
              child: _app(const HouseholdDashboardScreen()),
            ),
          );
        }
      });
    });

    // -----------------------------------------------------------------------
    // All Chores list
    // -----------------------------------------------------------------------
    group('ChoreListScreen', () {
      Widget screen(List<ChoreModel> chores) => ProviderScope(
            overrides: [
              choresNotifierProvider.overrideWith(
                () => _DataChoresNotifier(chores),
              ),
              householdsNotifierProvider.overrideWith(
                () => _DataHouseholdsNotifier([_household()]),
              ),
              membersNotifierProvider.overrideWith(
                () => _DataMembersNotifier([
                  _member(_kUserId, 'Test User'),
                  _member('user-2', 'Second User'),
                ]),
              ),
              currentUserProvider.overrideWith(
                (ref) async =>
                    const UserProfile(id: _kUserId, displayName: 'Test User'),
              ),
            ],
            child: _app(const ChoreListScreen(householdId: _kHouseholdId)),
          );

      testWidgets('empty list lays out cleanly', (tester) async {
        await _pumpAndExpectClean(tester, screen([]));
      });

      testWidgets('single chore lays out cleanly', (tester) async {
        await _pumpAndExpectClean(tester, screen([_chore()]));
      });

      testWidgets('many chores with every status lay out cleanly',
          (tester) async {
        final chores = [
          for (var i = 1; i <= 20; i++)
            _chore(
              id: 'c$i',
              title: 'Chore number $i',
              status: i % 4 == 0
                  ? 'complete'
                  : i % 4 == 1
                      ? 'overdue'
                      : i % 4 == 2
                          ? 'dismissed'
                          : 'pending',
              dueDate: DateTime(2026, 6, i),
            ),
        ];
        await _pumpAndExpectClean(tester, screen(chores));

        // Flip through every filter tab — each rebuild must stay clean.
        for (final tab in ['Pending', 'Overdue', 'Done', 'All']) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    });

    // -----------------------------------------------------------------------
    // Create chore form (+ copy-from-existing-task sheet, TASK-108/109)
    // -----------------------------------------------------------------------
    group('CreateChoreScreen', () {
      Widget form({List<ChoreTemplate> templates = const []}) =>
          ProviderScope(
            overrides: [
              householdsNotifierProvider.overrideWith(
                () => _DataHouseholdsNotifier([_household()]),
              ),
              membersNotifierProvider.overrideWith(
                () => _DataMembersNotifier([_member(_kUserId, 'Test User')]),
              ),
              choresNotifierProvider.overrideWith(
                () => _DataChoresNotifier([]),
              ),
              choreTemplatesProvider.overrideWith(
                () => _DataTemplatesNotifier(templates),
              ),
            ],
            child: _app(
              const CreateChoreScreen(householdId: _kHouseholdId),
            ),
          );

      testWidgets('default form and recurring variant lay out cleanly',
          (tester) async {
        _phoneView(tester);
        await _pumpAndExpectClean(tester, form());

        await tester.tap(find.byKey(const Key('type_recurring')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'form + category dropdown menu lay out cleanly on a NARROW phone '
          'and with LARGE text (TASK-112 repro: dropdown RenderFlex overflow)',
          (tester) async {
        // Narrow screen + large text is exactly the combo that overflowed the
        // category dropdown before TASK-112 (`isExpanded` + ellipsis).
        _narrowView(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(
          tester.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await _pumpAndExpectClean(tester, form());

        // Open the dropdown menu itself — its items are tight-constrained to
        // the button width, so they must ellipsize, not overflow.
        await tester.tap(find.byKey(const Key('category_dropdown')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Dismiss the menu.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('copy sheet with one template lays out cleanly',
          (tester) async {
        _phoneView(tester);
        await _pumpAndExpectClean(tester, form(templates: [_template(1)]));

        await tester.ensureVisible(
          find.byKey(const Key('copy_from_task_button')),
        );
        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('copy_task_t1')), findsOneWidget);
      });

      testWidgets(
          'copy sheet with MANY templates lays out cleanly on a phone '
          '(TASK-109: Flexible+shrinkWrap in a min-Column)',
          (tester) async {
        _phoneView(tester);
        final templates = [for (var i = 1; i <= 15; i++) _template(i)];
        await _pumpAndExpectClean(tester, form(templates: templates));

        await tester.ensureVisible(
          find.byKey(const Key('copy_from_task_button')),
        );
        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Sheet header is present (the button label also matches this text,
        // so assert on the sheet's row keys instead of the title).
        expect(find.byKey(const Key('copy_task_t1')), findsOneWidget);
        // The list must actually scroll to the last row — a sheet that
        // can't scroll is broken on a phone.
        await tester.scrollUntilVisible(
          find.byKey(const Key('copy_task_t15')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull);
        // The sheet is a draggable half-height panel, NOT full-screen (the
        // pre-TASK-109 sheet expanded to full height with many templates —
        // the user-visible defect this task was about).
        final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(sheetHeight, lessThan(screenHeight));
      });

      testWidgets(
          'copy sheet survives LANDSCAPE + LARGE TEXT (TASK-109 '
          'adversarial review: fixed header overflow at minChildSize)',
          (tester) async {
        // Short landscape surface with textScale 2.0: the sheet dragged to
        // minChildSize is ~72px tall — smaller than a fixed header would be.
        // The header scrolls with the list, so no overflow can occur.
        tester.view.physicalSize = const Size(640 * 2, 360 * 2);
        tester.view.devicePixelRatio = 2.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(
          tester.platformDispatcher.clearTextScaleFactorTestValue,
        );

        final templates = [for (var i = 1; i <= 10; i++) _template(i)];
        await _pumpAndExpectClean(tester, form(templates: templates));

        // Drag-scroll the (very tall at textScale 2.0) form to the copy
        // button — drag-based scrolling ends with the button fully in view,
        // unlike ensureVisible which can leave it at the viewport edge and
        // make the tap miss.
        await tester.scrollUntilVisible(
          find.byKey(const Key('copy_from_task_button')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('copy_from_task_button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The sheet must actually be open.
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text('Copy from existing task'),
          findsNWidgets(2),
          reason: 'form button + sheet header',
        );

        // Drag the sheet's header down — the sheet collapses toward
        // minChildSize (the danger zone for a fixed header) — then back up
        // to max. At every extent the single scrollable must lay out
        // cleanly (the header scrolls with the list, so nothing overflows).
        final sheetHeader = find.text('Copy from existing task').last;
        await tester.drag(sheetHeader, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.drag(sheetHeader, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // My Chores
    // -----------------------------------------------------------------------
    group('MyChoresScreen', () {
      Widget screen(List<ChoreModel> chores) => ProviderScope(
            overrides: [
              choresNotifierProvider.overrideWith(
                () => _DataChoresNotifier(chores),
              ),
              householdsNotifierProvider.overrideWith(
                () => _DataHouseholdsNotifier([_household()]),
              ),
              currentUserProvider.overrideWith(
                (ref) async =>
                    const UserProfile(id: _kUserId, displayName: 'Test User'),
              ),
              weeklyLeaderboardProvider(_kHouseholdId).overrideWith(
                (ref) async => _leaderboard(2),
              ),
            ],
            child: _app(const MyChoresScreen(householdId: _kHouseholdId)),
          );

      testWidgets('todo with overdue+pending, done tab, and empty all clean',
          (tester) async {
        final chores = [
          _chore(id: 'c1', title: 'Overdue task', status: 'overdue'),
          _chore(
            id: 'c2',
            title: 'Pending soon',
            status: 'pending',
            dueDate: DateTime(2026, 6, 26),
          ),
          _chore(
            id: 'c3',
            title: 'Pending later',
            status: 'pending',
            dueDate: DateTime(2026, 7, 10),
          ),
          _chore(id: 'c4', title: 'Done task', status: 'complete'),
          _chore(id: 'c5', title: 'Dismissed task', status: 'dismissed'),
        ];
        await _pumpAndExpectClean(tester, screen(chores));

        // Done tab
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Empty state
        await _pumpAndExpectClean(tester, screen([]));
      });
    });

    // -----------------------------------------------------------------------
    // Leaderboard
    // -----------------------------------------------------------------------
    group('LeaderboardScreen', () {
      Widget screen(int entryCount) => ProviderScope(
            overrides: [
              leaderboardProvider(_kHouseholdId).overrideWith(
                (ref) async => _leaderboard(entryCount),
              ),
              leaderboardScopeNotifierProvider.overrideWith(
                LeaderboardScopeNotifier.new,
              ),
              householdsNotifierProvider.overrideWith(
                () => _DataHouseholdsNotifier([_household()]),
              ),
              currentUserProvider.overrideWith(
                (ref) async =>
                    const UserProfile(id: _kUserId, displayName: 'Test User'),
              ),
            ],
            child: _app(
              const LeaderboardScreen(householdId: _kHouseholdId),
            ),
          );

      testWidgets('empty and populated leaderboards lay out cleanly',
          (tester) async {
        await _pumpAndExpectClean(tester, screen(0));
        await _pumpAndExpectClean(tester, screen(15));
      });
    });

    // -----------------------------------------------------------------------
    // Groceries
    // -----------------------------------------------------------------------
    group('GroceryListScreen', () {
      Widget screen(List<GroceryItemModel> items) => ProviderScope(
            overrides: [
              groceriesNotifierProvider.overrideWith(
                () => _DataGroceriesNotifier(items),
              ),
              householdsNotifierProvider.overrideWith(
                () => _DataHouseholdsNotifier([_household()]),
              ),
              currentUserProvider.overrideWith(
                (ref) async =>
                    const UserProfile(id: _kUserId, displayName: 'Test User'),
              ),
            ],
            child: _app(
              const GroceryListScreen(householdId: _kHouseholdId),
            ),
          );

      testWidgets('empty and populated grocery lists lay out cleanly',
          (tester) async {
        await _pumpAndExpectClean(tester, screen([]));
        await _pumpAndExpectClean(tester, screen([
          for (var i = 1; i <= 12; i++)
            _grocery('g$i', 'Item $i', purchased: i.isEven),
        ]));
      });
    });
  });
}

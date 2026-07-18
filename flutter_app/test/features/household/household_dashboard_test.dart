import 'dart:async';

import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/features/household/screens/household_dashboard_screen.dart';
import 'package:chore_app/features/household/widgets/household_card.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:chore_app/shared/widgets/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

/// Builds the dashboard with a predetermined list of households.
Widget buildDashboardWithData(List<HouseholdModel> households) {
  return ProviderScope(
    overrides: [
      householdsNotifierProvider.overrideWith(
        () => _DataHouseholdsNotifier(households),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const HouseholdDashboardScreen(),
    ),
  );
}

/// Builds the dashboard stuck in the loading state.
Widget buildDashboardLoading() {
  return ProviderScope(
    overrides: [
      householdsNotifierProvider.overrideWith(
        () => _LoadingHouseholdsNotifier(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const HouseholdDashboardScreen(),
    ),
  );
}

/// Builds the dashboard in an error state.
Widget buildDashboardError(String message) {
  return ProviderScope(
    overrides: [
      householdsNotifierProvider.overrideWith(
        () => _ErrorHouseholdsNotifier(message),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const HouseholdDashboardScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

/// Returns immediately with a fixed list of households.
class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);

  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

/// Stays in the loading state indefinitely.
class _LoadingHouseholdsNotifier extends HouseholdsNotifier {
  @override
  Future<List<HouseholdModel>> build() => Completer<List<HouseholdModel>>().future;
}

/// Immediately throws to produce an error state.
class _ErrorHouseholdsNotifier extends HouseholdsNotifier {
  _ErrorHouseholdsNotifier(this._message);

  final String _message;

  @override
  Future<List<HouseholdModel>> build() => Future.error(Exception(_message));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HouseholdDashboardScreen', () {
    // -----------------------------------------------------------------------
    // Loading state
    // -----------------------------------------------------------------------
    testWidgets('shows LoadingWidget when state is loading', (tester) async {
      await tester.pumpWidget(buildDashboardLoading());
      // Do not pump to settle — keep the loading state.
      await tester.pump();

      expect(find.byType(LoadingWidget), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Empty state
    // -----------------------------------------------------------------------
    testWidgets('shows "No households yet" when list is empty', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(find.text('No households yet'), findsOneWidget);
    });

    testWidgets('shows create button in empty state', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(find.byKey(const Key('empty_state_create_button')), findsOneWidget);
      expect(find.text('Create one'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // List state
    // -----------------------------------------------------------------------
    testWidgets('renders 2 HouseholdCards when list has 2 households',
        (tester) async {
      final households = [
        _household(id: 'h1', name: 'Smith Family', role: 'admin'),
        _household(id: 'h2', name: 'Jones Home', role: 'member'),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      expect(find.byType(HouseholdCard), findsNWidgets(2));
    });

    testWidgets('each card shows household name', (tester) async {
      final households = [
        _household(id: 'h1', name: 'Smith Family', role: 'admin'),
        _household(id: 'h2', name: 'Jones Home', role: 'member'),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      expect(find.text('Smith Family'), findsOneWidget);
      expect(find.text('Jones Home'), findsOneWidget);
    });

    testWidgets('each card shows the correct role badge', (tester) async {
      final households = [
        _household(id: 'h1', name: 'Smith Family', role: 'admin'),
        _household(id: 'h2', name: 'Jones Home', role: 'member'),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
    });

    testWidgets('each card shows member count', (tester) async {
      final households = [
        _household(id: 'h1', name: 'Smith Family', memberCount: 4),
        _household(id: 'h2', name: 'Jones Home', memberCount: 2),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Role badge colours
    // -----------------------------------------------------------------------
    testWidgets('Admin badge has amber background', (tester) async {
      final households = [
        _household(id: 'h1', name: 'Admin Home', role: 'admin'),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      // The Key is placed directly on the Chip widget in HouseholdCard.
      final badgeFinder = find.byKey(const Key('role_badge_admin_h1'));
      expect(badgeFinder, findsOneWidget);

      final chip = tester.widget<Chip>(badgeFinder);
      final bg = chip.backgroundColor!;
      final r = (bg.r * 255.0).round().clamp(0, 255);
      final g = (bg.g * 255.0).round().clamp(0, 255);
      final b = (bg.b * 255.0).round().clamp(0, 255);
      // Amber 100 has high red + green, low blue.
      expect(r, greaterThan(b));
      expect(g, greaterThan(b));
    });

    testWidgets('Member badge has grey background', (tester) async {
      final households = [
        _household(id: 'h1', name: 'Member Home', role: 'member'),
      ];

      await tester.pumpWidget(buildDashboardWithData(households));
      await tester.pump();

      final badgeFinder = find.byKey(const Key('role_badge_member_h1'));
      expect(badgeFinder, findsOneWidget);

      final chip = tester.widget<Chip>(badgeFinder);
      final bg = chip.backgroundColor!;
      final r = (bg.r * 255.0).round().clamp(0, 255);
      final g = (bg.g * 255.0).round().clamp(0, 255);
      final b = (bg.b * 255.0).round().clamp(0, 255);
      // Grey shade 200 has similar R, G, B channel values.
      final diff = (r - g).abs() + (g - b).abs();
      expect(diff, lessThan(20));
    });

    // -----------------------------------------------------------------------
    // Error state
    // -----------------------------------------------------------------------
    testWidgets('shows error widget when provider returns an error',
        (tester) async {
      await tester.pumpWidget(buildDashboardError('Network error'));
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // App bar
    // -----------------------------------------------------------------------
    testWidgets('renders "My Households" title in app bar', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(find.text('My Households'), findsOneWidget);
    });

    testWidgets('renders logout button in app bar', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(find.byKey(const Key('logout_button')), findsOneWidget);
    });

    testWidgets('renders join-by-invite button in app bar', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(find.byKey(const Key('join_by_invite_button')), findsOneWidget);
    });

    testWidgets('renders server settings button in app bar', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(
        find.byKey(const Key('dashboard_server_settings_button')),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // FAB
    // -----------------------------------------------------------------------
    testWidgets('renders FAB for creating a household', (tester) async {
      await tester.pumpWidget(buildDashboardWithData([]));
      await tester.pump();

      expect(
        find.byKey(const Key('create_household_fab')),
        findsOneWidget,
      );
    });
  });
}

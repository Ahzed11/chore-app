import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chore_app/features/groceries/models/grocery_item_model.dart';
import 'package:chore_app/features/groceries/providers/groceries_provider.dart';
import 'package:chore_app/features/groceries/screens/grocery_list_screen.dart';
import 'package:chore_app/features/household/models/household_model.dart';
import 'package:chore_app/features/household/providers/household_provider.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:chore_app/shared/widgets/loading_widget.dart';

const _kHouseholdId = 'hh-1';
const _kUserId = 'user-1';

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _DataGroceriesNotifier extends GroceriesNotifier {
  _DataGroceriesNotifier(this._items);

  final List<GroceryItemModel> _items;
  bool toggleCalled = false;

  @override
  Future<List<GroceryItemModel>> build(String arg) async => _items;

  @override
  Future<GroceryItemModel> togglePurchased(GroceryItemModel item) async {
    toggleCalled = true;
    final updated = GroceryItemModel(
      id: item.id,
      householdId: item.householdId,
      addedById: item.addedById,
      addedByName: item.addedByName,
      name: item.name,
      quantity: item.quantity,
      notes: item.notes,
      isPurchased: !item.isPurchased,
      purchasedById: item.isPurchased ? null : _kUserId,
      purchasedByName: item.isPurchased ? null : 'Test User',
      purchasedAt: item.isPurchased ? null : DateTime(2026, 8, 5),
      createdAt: item.createdAt,
    );
    _items
      ..clear()
      ..addAll([updated]);
    // Mirror the real notifier: publish the new list so the UI rebuilds.
    state = AsyncData(List<GroceryItemModel>.of(_items));
    return updated;
  }
}

class _LoadingGroceriesNotifier extends GroceriesNotifier {
  @override
  Future<List<GroceryItemModel>> build(String arg) async {
    // Never completes during the test's single pump.
    return Completer<List<GroceryItemModel>>().future;
  }
}

class _EmptyGroceriesNotifier extends GroceriesNotifier {
  @override
  Future<List<GroceryItemModel>> build(String arg) async => const [];
}

class _DataHouseholdsNotifier extends HouseholdsNotifier {
  _DataHouseholdsNotifier(this._households);

  final List<HouseholdModel> _households;

  @override
  Future<List<HouseholdModel>> build() async => _households;
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

HouseholdModel _household() => HouseholdModel(
      id: _kHouseholdId,
      name: 'Test Household',
      role: 'admin',
      memberCount: 2,
      createdAt: DateTime(2026, 1, 1),
    );

GroceryItemModel _item({
  required String id,
  required String name,
  String? quantity,
  String? notes,
  bool isPurchased = false,
  String? purchasedByName,
}) {
  return GroceryItemModel(
    id: id,
    householdId: _kHouseholdId,
    addedById: _kUserId,
    addedByName: 'Test User',
    name: name,
    quantity: quantity,
    notes: notes,
    isPurchased: isPurchased,
    purchasedById: isPurchased ? _kUserId : null,
    purchasedByName: purchasedByName,
    purchasedAt: isPurchased ? DateTime(2026, 8, 5) : null,
    createdAt: DateTime(2026, 8, 5),
  );
}

// ---------------------------------------------------------------------------
// Widget builder helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required GroceriesNotifier Function() groceriesNotifier,
  List<HouseholdModel>? households,
}) {
  return ProviderScope(
    overrides: [
      groceriesNotifierProvider.overrideWith(groceriesNotifier),
      householdsNotifierProvider.overrideWith(
        () => _DataHouseholdsNotifier(households ?? [_household()]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const GroceryListScreen(householdId: _kHouseholdId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GroceryListScreen', () {
    testWidgets('shows LoadingWidget while groceries are loading',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: _LoadingGroceriesNotifier.new),
      );
      await tester.pump(); // single frame — keep in loading

      expect(find.byType(LoadingWidget), findsOneWidget);
    });

    testWidgets('shows empty state when no items', (tester) async {
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: _EmptyGroceriesNotifier.new),
      );
      await tester.pump();

      expect(find.text('No items yet'), findsOneWidget);
    });

    testWidgets('renders items with quantity and purchased state',
        (tester) async {
      final items = [
        _item(id: 'i1', name: 'Milk', quantity: '2 cartons'),
        _item(
          id: 'i2',
          name: 'Bread',
          isPurchased: true,
          purchasedByName: 'Test User',
        ),
      ];
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: () => _DataGroceriesNotifier(items)),
      );
      await tester.pump();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('2 cartons'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Purchased'), findsOneWidget);
      expect(find.text('Purchased by Test User'), findsOneWidget);
      expect(find.text('No items yet'), findsNothing);
    });

    testWidgets('tapping the checkbox toggles purchase state',
        (tester) async {
      final items = [_item(id: 'i1', name: 'Milk')];
      final notifier = _DataGroceriesNotifier(items);
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: () => notifier),
      );
      await tester.pump();

      // Tap the unchecked radio circle (toggle to purchased).
      await tester.tap(find.byIcon(Icons.radio_button_unchecked_rounded));
      await tester.pumpAndSettle();

      expect(notifier.toggleCalled, isTrue);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('shows the bottom nav with Groceries selected',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: _EmptyGroceriesNotifier.new),
      );
      await tester.pump();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('All Chores'), findsOneWidget);
      expect(find.text('My Chores'), findsOneWidget);
      expect(find.text('Leaderboard'), findsOneWidget);
      // "Groceries" appears twice: the nav destination label and the screen
      // header title (TASK-098 made the header a static feature title).
      expect(find.text('Groceries'), findsNWidgets(2));
    });

    testWidgets(
        'header title is "Groceries", not the household name (TASK-098)',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: _EmptyGroceriesNotifier.new),
      );
      await tester.pump();

      // Regression: the header used to resolve the household name and show
      // it as the screen title (e.g. "Test Household") once the household
      // provider loaded. It must always be the static feature title.
      expect(find.text('Groceries'), findsNWidgets(2));
      expect(find.text('Test Household'), findsNothing);
    });

    testWidgets('has no back-arrow button and no AppBar (TASK-091)',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(groceriesNotifier: _EmptyGroceriesNotifier.new),
      );
      await tester.pump();

      // The screen is a bottom-nav tab; navigation happens via the bottom
      // bar and the system back button. A visible back arrow that jumps to
      // the household picker makes no sense here.
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });
  });
}

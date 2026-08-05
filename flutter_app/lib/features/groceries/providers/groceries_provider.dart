import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../models/grocery_item_model.dart';

// ---------------------------------------------------------------------------
// Groceries notifier
// ---------------------------------------------------------------------------

class GroceriesNotifier extends FamilyAsyncNotifier<List<GroceryItemModel>, String> {
  @override
  Future<List<GroceryItemModel>> build(String arg) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<List<dynamic>>(
      ApiEndpoints.householdGroceries(arg),
    );
    final items = response.data ?? [];
    return items.cast<Map<String, dynamic>>().map(GroceryItemModel.fromJson).toList();
  }

  /// Adds a new item to the grocery list.
  Future<void> addItem(String name, {String? quantity, String? notes}) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      ApiEndpoints.householdGroceries(householdId),
      data: {
        'name': name,
        if (quantity != null && quantity.isNotEmpty) 'quantity': quantity,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    ref.invalidateSelf();
    await future;
  }

  /// Updates an existing item's name/quantity/notes.
  Future<void> updateItem(String itemId, Map<String, dynamic> body) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      ApiEndpoints.groceryItem(householdId, itemId),
      data: body,
    );
    ref.invalidateSelf();
    await future;
  }

  /// Deletes an item from the grocery list.
  Future<void> deleteItem(String itemId) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);
    await dio.delete<void>(
      ApiEndpoints.groceryItem(householdId, itemId),
    );
    ref.invalidateSelf();
    await future;
  }

  /// Toggles an item's purchased state with an optimistic update.
  ///
  /// On failure the previous state is restored and the error is rethrown so
  /// callers can surface a message to the user. Returns the server's
  /// authoritative updated item on success.
  Future<GroceryItemModel> togglePurchased(GroceryItemModel item) async {
    final householdId = arg;
    final dio = ref.read(dioProvider);

    // Snapshot current state so we can revert on failure.
    final previousState = state;

    // Optimistic update: flip the flag immediately.
    final optimistic = GroceryItemModel(
      id: item.id,
      householdId: item.householdId,
      addedById: item.addedById,
      addedByName: item.addedByName,
      name: item.name,
      quantity: item.quantity,
      notes: item.notes,
      isPurchased: !item.isPurchased,
      purchasedById: item.isPurchased ? null : item.purchasedById,
      purchasedByName: item.isPurchased ? null : item.purchasedByName,
      purchasedAt: item.isPurchased ? null : item.purchasedAt,
      createdAt: item.createdAt,
    );
    state = state.whenData((items) => [
      for (final i in items) if (i.id == item.id) optimistic else i,
    ]);

    try {
      final response = await dio.post<Map<String, dynamic>>(
        item.isPurchased
            ? ApiEndpoints.groceryUnpurchase(householdId, item.id)
            : ApiEndpoints.groceryPurchase(householdId, item.id),
      );
      final updated = GroceryItemModel.fromJson(response.data!);
      state = state.whenData((items) => [
        for (final i in items) if (i.id == item.id) updated else i,
      ]);
      return updated;
    } catch (e) {
      state = previousState; // revert on failure
      rethrow;
    }
  }

  /// Forces a fresh fetch from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final groceriesNotifierProvider = AsyncNotifierProviderFamily<
    GroceriesNotifier, List<GroceryItemModel>, String>(GroceriesNotifier.new);

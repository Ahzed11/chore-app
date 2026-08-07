import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/friendly_error.dart';
import '../../../shared/widgets/accessible_tap.dart';
import '../../../shared/widgets/app_bottom_nav_bar.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../household/providers/household_provider.dart';
import '../models/grocery_item_model.dart';
import '../providers/groceries_provider.dart';

// ---------------------------------------------------------------------------
// Constants (teal palette, matching chore_list_screen)
// ---------------------------------------------------------------------------

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF7F9794);
const _borderLight = Color(0xFFE6EDEC);
const _green = Color(0xFF4CAF50);

// ---------------------------------------------------------------------------
// GroceryListScreen
// ---------------------------------------------------------------------------

class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _addItem() async {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    _addController.clear();
    try {
      await ref
          .read(groceriesNotifierProvider(widget.householdId).notifier)
          .addItem(name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _togglePurchased(GroceryItemModel item) async {
    try {
      await ref
          .read(groceriesNotifierProvider(widget.householdId).notifier)
          .togglePurchased(item);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _deleteItem(GroceryItemModel item) async {
    try {
      await ref
          .read(groceriesNotifierProvider(widget.householdId).notifier)
          .deleteItem(item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _editItem(GroceryItemModel item) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditItemSheet(item: item),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(groceriesNotifierProvider(widget.householdId).notifier)
          .updateItem(item.id, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final groceriesAsync =
        ref.watch(groceriesNotifierProvider(widget.householdId));
    final householdName = ref
        .watch(householdsNotifierProvider)
        .whenOrNull(data: (h) => h
            .where((h) => h.id == widget.householdId)
            .map((h) => h.name)
            .firstOrNull);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/households');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — inline, matching the other tab screens (no AppBar).
              _GroceryListHeader(name: householdName ?? 'Groceries'),

              // Add-item row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('grocery_add_field'),
                        controller: _addController,
                        decoration: InputDecoration(
                          hintText: 'Add an item to buy…',
                          filled: true,
                          fillColor: const Color(0xFFF5F8F7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addItem(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AccessibleTap(
                      onTap: _addItem,
                      label: 'Add grocery item',
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _teal,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: groceriesAsync.when(
                  loading: () =>
                      const LoadingWidget(message: 'Loading groceries...'),
                  error: (error, _) => AppErrorWidget(
                    error: error,
                    onRetry: () => ref
                        .read(
                          groceriesNotifierProvider(widget.householdId).notifier,
                        )
                        .refresh(),
                  ),
                  data: (items) {
                    final unpurchased =
                        items.where((i) => !i.isPurchased).toList();
                    final purchased =
                        items.where((i) => i.isPurchased).toList();
                    return RefreshIndicator(
                      color: _teal,
                      onRefresh: () => ref
                          .read(
                            groceriesNotifierProvider(widget.householdId)
                                .notifier,
                          )
                          .refresh(),
                      child: items.isEmpty
                          ? const _EmptyState()
                          : ListView(
                              key: const Key('grocery_list'),
                              padding: const EdgeInsets.only(
                                top: 4,
                                bottom: 100,
                              ),
                              children: [
                                if (unpurchased.isNotEmpty) ...[
                                  for (final item in unpurchased)
                                    _GroceryItemTile(
                                      item: item,
                                      onToggle: () =>
                                          _togglePurchased(item),
                                      onEdit: () => _editItem(item),
                                      onDelete: () => _deleteItem(item),
                                    ),
                                ],
                                if (purchased.isNotEmpty) ...[
                                  const _SectionLabel('Purchased'),
                                  for (final item in purchased)
                                    _GroceryItemTile(
                                      item: item,
                                      onToggle: () =>
                                          _togglePurchased(item),
                                      onEdit: () => _editItem(item),
                                      onDelete: () => _deleteItem(item),
                                    ),
                                ],
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNavBar(
          householdId: widget.householdId,
          currentIndex: 3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — inline, matching _ChoreListHeader on the chores tab (TASK-090)
// ---------------------------------------------------------------------------

class _GroceryListHeader extends StatelessWidget {
  const _GroceryListHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: _darkText,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item tile
// ---------------------------------------------------------------------------

class _GroceryItemTile extends StatelessWidget {
  const _GroceryItemTile({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final GroceryItemModel item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: item.isPurchased ? const Color(0xFFF5F8F7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderLight),
      ),
      child: Row(
        children: [
          // Checkbox (48dp target via AccessibleTap)
          AccessibleTap(
            onTap: onToggle,
            label: item.isPurchased
                ? 'Mark ${item.name} as not purchased'
                : 'Mark ${item.name} as purchased',
            child: SizedBox(
              width: 48,
              height: 56,
              child: Icon(
                item.isPurchased
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: item.isPurchased ? _green : _secondaryText,
                size: 26,
              ),
            ),
          ),
          // Main content (tap to edit)
          Expanded(
            child: AccessibleTap(
              onTap: onEdit,
              label: 'Edit ${item.name}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: item.isPurchased
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.isPurchased
                                  ? _secondaryText
                                  : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.quantity != null &&
                            item.quantity!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            item.quantity!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.notes != null && item.notes!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.isPurchased &&
                        item.purchasedByName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Purchased by ${item.purchasedByName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Delete (48dp target)
          AccessibleTap(
            onTap: onDelete,
            label: 'Delete ${item.name}',
            child: const SizedBox(
              width: 48,
              height: 56,
              child: Icon(
                Icons.delete_outline_rounded,
                color: _secondaryText,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label ("Purchased")
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _secondaryText,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: _secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'No items yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an item above to start your grocery list.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _secondaryText,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit sheet
// ---------------------------------------------------------------------------

class _EditItemSheet extends StatefulWidget {
  const _EditItemSheet({required this.item});

  final GroceryItemModel item;

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _quantityController = TextEditingController(text: widget.item.quantity);
    _notesController = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final body = <String, dynamic>{
      'name': _nameController.text.trim(),
    };
    final quantity = _quantityController.text.trim();
    final notes = _notesController.text.trim();
    if (quantity.isNotEmpty) body['quantity'] = quantity;
    if (notes.isNotEmpty) body['notes'] = notes;
    Navigator.of(context).pop(body);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit item',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('edit_item_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_item_quantity_field'),
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_item_notes_field'),
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('save_item_button'),
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

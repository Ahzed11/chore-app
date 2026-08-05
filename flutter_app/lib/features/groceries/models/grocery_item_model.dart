/// GroceryItemModel mirrors the backend `GroceryItemResponse` schema.
class GroceryItemModel {
  const GroceryItemModel({
    required this.id,
    required this.householdId,
    this.addedById,
    this.addedByName,
    required this.name,
    this.quantity,
    this.notes,
    required this.isPurchased,
    this.purchasedById,
    this.purchasedByName,
    this.purchasedAt,
    required this.createdAt,
  });

  final String id;
  final String householdId;
  final String? addedById;
  final String? addedByName;
  final String name;
  final String? quantity;
  final String? notes;
  final bool isPurchased;
  final String? purchasedById;
  final String? purchasedByName;
  final DateTime? purchasedAt;
  final DateTime createdAt;

  factory GroceryItemModel.fromJson(Map<String, dynamic> json) {
    return GroceryItemModel(
      id: json['id'] as String,
      householdId: json['household_id'] as String,
      addedById: json['added_by_id'] as String?,
      addedByName: json['added_by_name'] as String?,
      name: json['name'] as String,
      quantity: json['quantity'] as String?,
      notes: json['notes'] as String?,
      isPurchased: json['is_purchased'] as bool,
      purchasedById: json['purchased_by_id'] as String?,
      purchasedByName: json['purchased_by_name'] as String?,
      purchasedAt: json['purchased_at'] != null
          ? DateTime.parse(json['purchased_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'added_by_id': addedById,
      'added_by_name': addedByName,
      'name': name,
      'quantity': quantity,
      'notes': notes,
      'is_purchased': isPurchased,
      'purchased_by_id': purchasedById,
      'purchased_by_name': purchasedByName,
      'purchased_at': purchasedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

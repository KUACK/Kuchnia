class FoodItem {
  final String name;
  final String quantity;
  final String expiryDate;
  final ExpiryStatus status;

  const FoodItem({
    required this.name,
    required this.quantity,
    required this.expiryDate,
    required this.status,
  });
}

enum ExpiryStatus {
  critical, // czerwona kropka
  warning, // pomarańczowa kropka
  ok, // żółta kropka
}

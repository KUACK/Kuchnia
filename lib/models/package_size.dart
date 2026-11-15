class PackageSize {
  final double value;
  final String unit;

  const PackageSize({required this.value, required this.unit});

  static const allowedUnits = ['szt.', 'g', 'kg', 'ml', 'l'];

  static PackageSize? tryParse(String? input) {
    if (input == null) return null;

    final text = input
        .trim()
        .toLowerCase()
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u202f', ' ');

    if (text.isEmpty) return null;

    // Rozpoznajemy tylko prosty, jednoznaczny zapis.
    // Np. "400 g", "1 l", "0,5 kg".
    // Wielopaki typu "6 x 100 g" wymagają ręcznego sprawdzenia.
    final match = RegExp(
      r'^([0-9]+(?:[.,][0-9]+)?)\s*'
      r'(kg|ml|cl|mg|g|l|szt\.?|pcs?\.?)$',
    ).firstMatch(text);

    if (match == null) return null;

    final parsedValue = double.tryParse(match.group(1)!.replaceAll(',', '.'));

    if (parsedValue == null || !parsedValue.isFinite || parsedValue <= 0) {
      return null;
    }

    var value = parsedValue;
    var unit = match.group(2)!;

    switch (unit) {
      case 'cl':
        value *= 10;
        unit = 'ml';
        break;
      case 'mg':
        value /= 1000;
        unit = 'g';
        break;
      case 'szt':
      case 'szt.':
      case 'pc':
      case 'pc.':
      case 'pcs':
      case 'pcs.':
        unit = 'szt.';
        break;
    }

    if (!allowedUnits.contains(unit) ||
        !value.isFinite ||
        value <= 0 ||
        value > 1000000) {
      return null;
    }

    return PackageSize(value: value, unit: unit);
  }

  String get inputText {
    return value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
  }
}

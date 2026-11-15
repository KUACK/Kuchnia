import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ProductLookupStatus {
  found,
  notFound,
  invalidBarcode,
  timeout,
  networkError,
  rateLimited,
  serverError,
  invalidResponse,
}

class ProductLookupResult {
  final ProductLookupStatus status;
  final String barcode;
  final String? productName;
  final String? brands;
  final String? packageQuantity;
  final String? imageUrl;
  final List<String> categoryTags;
  final String? suggestedCategory;

  const ProductLookupResult({
    required this.status,
    required this.barcode,
    this.productName,
    this.brands,
    this.packageQuantity,
    this.imageUrl,
    this.categoryTags = const [],
    this.suggestedCategory,
  });
}

class OpenFoodFactsService {
  final String contact;

  bool _isSearching = false;
  DateTime? _nextAllowedRequest;

  OpenFoodFactsService({required this.contact}) {
    if (contact.trim().isEmpty) {
      throw ArgumentError('Podaj kontakt do autora aplikacji.');
    }
  }

  // To ograniczone reguły naszej aplikacji, nie pełna klasyfikacja OFF.
  // Porównujemy całe identyfikatory, a nie fragmenty nazw.
  static const Map<String, Set<String>> _categoryRules = {
    'Nabiał': {
      'en:dairies',
      'en:milks',
      'en:yogurts',
      'en:cheeses',
      'en:butters',
      'en:creams',
      'en:fermented-milk-products',
    },
    'Mięso i ryby': {
      'en:meats',
      'en:poultries',
      'en:beef',
      'en:pork',
      'en:fishes',
      'en:seafood',
      'en:sausages',
    },
    'Warzywa': {'en:vegetables', 'en:fresh-vegetables', 'en:frozen-vegetables'},
    'Owoce': {'en:fruits', 'en:fresh-fruits', 'en:frozen-fruits'},
    'Pieczywo': {'en:breads', 'en:bread-rolls', 'en:flatbreads'},
    'Produkty suche': {
      'en:pastas',
      'en:rices',
      'en:flours',
      'en:rolled-oats',
      'en:couscous',
    },
    'Napoje': {
      'en:beverages',
      'en:waters',
      'en:fruit-juices',
      'en:carbonated-drinks',
      'en:plant-based-beverages',
    },
  };

  Future<ProductLookupResult> findByBarcode(String input) async {
    final barcode = input.trim();

    ProductLookupResult result(
      ProductLookupStatus status, {
      String? productName,
      String? brands,
      String? packageQuantity,
      String? imageUrl,
      List<String> categoryTags = const [],
      String? suggestedCategory,
    }) {
      return ProductLookupResult(
        status: status,
        barcode: barcode,
        productName: productName,
        brands: brands,
        packageQuantity: packageQuantity,
        imageUrl: imageUrl,
        categoryTags: categoryTags,
        suggestedCategory: suggestedCategory,
      );
    }

    final isValid = RegExp(
      r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$',
    ).hasMatch(barcode);

    if (!isValid) {
      return result(ProductLookupStatus.invalidBarcode);
    }

    final now = DateTime.now();
    final nextAllowed = _nextAllowedRequest;

    if (_isSearching || (nextAllowed != null && now.isBefore(nextAllowed))) {
      return result(ProductLookupStatus.rateLimited);
    }

    _isSearching = true;
    _nextAllowedRequest = now.add(const Duration(seconds: 5));

    final client = http.Client();

    try {
      final uri = Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/$barcode',
        {
          'lc': 'pl',
          'fields': [
            'product_name',
            'product_name_pl',
            'brands',
            'quantity',
            'selected_images',
            'image_front_small_url',
            'categories_tags',
          ].join(','),
        },
      );

      final response = await client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'KuchniaPlus/1.0.0 (Android; ${contact.trim()})',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 429) {
        _nextAllowedRequest = DateTime.now().add(const Duration(minutes: 1));

        return result(ProductLookupStatus.rateLimited);
      }

      if (response.statusCode != 200 && response.statusCode != 404) {
        return result(ProductLookupStatus.serverError);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        return result(ProductLookupStatus.invalidResponse);
      }

      if (decoded['status'] == 0) {
        return result(ProductLookupStatus.notFound);
      }

      if (response.statusCode != 200 || decoded['status'] != 1) {
        return result(ProductLookupStatus.invalidResponse);
      }

      final product = decoded['product'];

      if (product is! Map<String, dynamic>) {
        return result(ProductLookupStatus.invalidResponse);
      }

      final name =
          _nonEmptyString(product['product_name_pl']) ??
          _nonEmptyString(product['product_name']);

      final categoryTags = _readCategoryTags(product['categories_tags']);

      return result(
        ProductLookupStatus.found,
        productName: name,
        brands: _nonEmptyString(product['brands']),
        packageQuantity: _nonEmptyString(product['quantity']),
        imageUrl: _findFrontImage(product),
        categoryTags: categoryTags,
        suggestedCategory: _suggestCategory(categoryTags),
      );
    } on TimeoutException {
      return result(ProductLookupStatus.timeout);
    } on http.ClientException {
      return result(ProductLookupStatus.networkError);
    } on FormatException {
      return result(ProductLookupStatus.invalidResponse);
    } catch (_) {
      return result(ProductLookupStatus.invalidResponse);
    } finally {
      client.close();
      _isSearching = false;
    }
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String) return null;

    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  List<String> _readCategoryTags(dynamic value) {
    if (value is! List) return const [];

    return List<String>.unmodifiable(
      value
          .whereType<String>()
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet(),
    );
  }

  String? _suggestCategory(List<String> tags) {
    if (tags.isEmpty) return null;

    final tagSet = tags.toSet();
    final matches = <String>{};

    for (final rule in _categoryRules.entries) {
      if (rule.value.any(tagSet.contains)) {
        matches.add(rule.key);
      }
    }

    // Przy braku dopasowania lub konflikcie nie zgadujemy.
    if (matches.length != 1) return null;

    return matches.single;
  }

  String? _httpsImageUrl(dynamic value) {
    final text = _nonEmptyString(value);

    if (text == null) return null;

    final uri = Uri.tryParse(text);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    return uri.toString();
  }

  String? _findFrontImage(Map<String, dynamic> product) {
    final selectedImages = product['selected_images'];

    if (selectedImages is Map<String, dynamic>) {
      final front = selectedImages['front'];

      if (front is Map<String, dynamic>) {
        final display = front['display'];

        if (display is Map<String, dynamic>) {
          final polishImage = _httpsImageUrl(display['pl']);

          if (polishImage != null) return polishImage;

          final englishImage = _httpsImageUrl(display['en']);

          if (englishImage != null) return englishImage;

          for (final value in display.values) {
            final image = _httpsImageUrl(value);

            if (image != null) return image;
          }
        }
      }
    }

    return _httpsImageUrl(product['image_front_small_url']);
  }
}

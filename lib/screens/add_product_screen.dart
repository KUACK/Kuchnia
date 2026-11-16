import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/expiration_date_field.dart';

import '../models/package_size.dart';
import '../services/open_food_facts_service.dart';
import 'product_entry_screen.dart';
import 'expiration_date_scan_screen.dart';

class AddProductScreen extends StatefulWidget {
  final String householdId;

  const AddProductScreen({super.key, required this.householdId});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _packageSizeController = TextEditingController();
  final _packageCountController = TextEditingController(text: '1');

  final _lookupService = OpenFoodFactsService(
    contact: 'grzegorzloban@gmail.com',
  );

  String _category = 'Inne';
  bool _categoryWasSelectedManually = false;

  String _unit = 'szt.';
  String _storageLocation = 'Lodówka';
  bool _storageLocationWasSelectedManually = false;

  DateTime? _expirationDate;
  bool _withoutExpirationDate = false;

  bool _isSaving = false;
  bool _isLookupOpen = false;
  bool _isInitialEntryPending = true;

  String? _errorMessage;
  String? _lookupMessage;

  ProductLookupResult? _catalogProduct;

  static const _categories = [
    'Nabiał',
    'Mięso i ryby',
    'Warzywa',
    'Owoce',
    'Pieczywo',
    'Produkty suche',
    'Napoje',
    'Inne',
  ];

  static const _units = ['szt.', 'g', 'kg', 'ml', 'l'];

  static const _locations = ['Lodówka', 'Zamrażarka', 'Szafka', 'Inne'];

  static const _imageHeaders = {
    'User-Agent': 'KuchniaPlus/1.0.0 (Android; grzegorzloban@gmail.com)',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _lookupProduct();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _packageSizeController.dispose();
    _packageCountController.dispose();
    super.dispose();
  }

  void _suggestStorageLocation() {
    if (_storageLocationWasSelectedManually) return;

    final suggestedLocation = switch (_category) {
      'Nabiał' => 'Lodówka',
      'Mięso i ryby' => 'Lodówka',
      'Pieczywo' => 'Szafka',
      'Produkty suche' => 'Szafka',
      _ => null,
    };

    if (suggestedLocation != null) {
      _storageLocation = suggestedLocation;
    }
  }

  double? _parseNumber(String? value) {
    return double.tryParse((value ?? '').trim().replaceAll(',', '.'));
  }

  int? _parsePackageCount(String? value) {
    final text = (value ?? '').trim();

    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;

    return int.tryParse(text);
  }

  double? get _totalQuantity {
    final size = _parseNumber(_packageSizeController.text);
    final count = _parsePackageCount(_packageCountController.text);

    if (size == null ||
        !size.isFinite ||
        size <= 0 ||
        count == null ||
        count < 1) {
      return null;
    }

    final total = size * count;

    return total.isFinite ? total : null;
  }

  String? _suggestedName(ProductLookupResult product) {
    final name = product.productName?.trim();

    if (name == null || name.isEmpty) return null;

    final brands = product.brands?.trim();

    if (brands == null || brands.isEmpty) return name;

    final missingBrands = brands
        .split(',')
        .map((brand) => brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .where((brand) => !name.toLowerCase().contains(brand.toLowerCase()))
        .toList();

    if (missingBrands.isEmpty) return name;

    return '$name (${missingBrands.join(', ')})';
  }

  Future<void> _lookupProduct() async {
    if (_isSaving || _isLookupOpen) return;

    FocusScope.of(context).unfocus();

    final isInitialEntry = _isInitialEntryPending;

    setState(() {
      _isLookupOpen = true;
    });

    try {
      final result = await Navigator.of(context).push<ProductLookupResult>(
        PageRouteBuilder<ProductLookupResult>(
          pageBuilder: (context, animation, secondaryAnimation) {
            return ProductEntryScreen(service: _lookupService);
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );

      if (!mounted) return;

      if (result == null) {
        if (isInitialEntry && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }

        return;
      }

      setState(() {
        _isInitialEntryPending = false;
      });

      if (result.status != ProductLookupStatus.found) {
        setState(() {
          _catalogProduct = null;
          _lookupMessage = result.barcode.isEmpty
              ? 'Uzupełnij dane produktu ręcznie.'
              : 'Nie znaleziono produktu w katalogu. '
                    'Uzupełnij dane ręcznie. '
                    'Dotychczasowe dane formularza zachowano.';
        });

        return;
      }

      final suggestedName = _suggestedName(result);
      final suggestedPackage = PackageSize.tryParse(result.packageQuantity);

      final rawCategory = result.suggestedCategory;
      final suggestedCategory = _categories.contains(rawCategory)
          ? rawCategory
          : null;

      final canApplyCategory =
          !_categoryWasSelectedManually && suggestedCategory != null;

      final warnings = <String>[];

      if (suggestedName == null) {
        warnings.add('Brak nazwy w katalogu — wpisz ją ręcznie.');
      } else if (suggestedName.length > 120) {
        warnings.add(
          'Podpowiedziana nazwa przekracza 120 znaków — '
          'skróć ją przed zapisaniem.',
        );
      }

      if (suggestedPackage == null) {
        warnings.add(
          'Brak jednoznacznej wielkości opakowania — sprawdź ją na etykiecie.',
        );
      }

      setState(() {
        if (suggestedName != null) {
          _nameController.text = suggestedName;
        }

        if (suggestedPackage != null) {
          _packageSizeController.text = suggestedPackage.inputText;
          _unit = suggestedPackage.unit;
        }

        if (canApplyCategory) {
          _category = suggestedCategory;
          _suggestStorageLocation();
        }

        _catalogProduct = result;
        _lookupMessage = warnings.isEmpty ? null : warnings.join(' ');
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Nie udało się otworzyć wyszukiwania produktu. '
            'Możesz uzupełnić formularz ręcznie.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLookupOpen = false;
          _isInitialEntryPending = false;
        });
      }
    }
  }

  void _showImageZoom(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      headers: _imageHeaders,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Zdjęcie: Open Food Facts (CC BY-SA)',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCatalogPreview(ProductLookupResult product) {
    final imageUrl = product.imageUrl;

    if (imageUrl == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showImageZoom(imageUrl),
      child: SizedBox(
        width: double.infinity,
        height: 200,
        child: Image.network(
          imageUrl,
          key: ValueKey(imageUrl),
          fit: BoxFit.contain,
          semanticLabel: 'Zdjęcie opakowania. Kliknij, aby powiększyć',
          headers: _imageHeaders,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Future<void> _scanExpirationDate() async {
    if (_isSaving || _isLookupOpen) return;

    FocusScope.of(context).unfocus();

    final scanned = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => const ExpirationDateScanScreen(),
      ),
    );

    if (!mounted || scanned == null) return;

    setState(() {
      _expirationDate = scanned;
      _withoutExpirationDate = false;
      _errorMessage = null;
    });
  }

  Widget _buildExpirationDateField() {
    return ExpirationDateField(
      date: _expirationDate,
      withoutExpirationDate: _withoutExpirationDate,
      enabled: !(_isSaving || _isLookupOpen),
      onScanRequested: _scanExpirationDate,
      onDateSelected: (date) {
        if (!mounted || _isSaving || _isLookupOpen) return;
        setState(() {
          _expirationDate = date;
          _withoutExpirationDate = false;
          _errorMessage = null;
        });
      },
      onWithoutExpirationDate: () {
        if (!mounted || _isSaving || _isLookupOpen) return;
        setState(() {
          _expirationDate = null;
          _withoutExpirationDate = true;
          _errorMessage = null;
        });
      },
    );
  }

  Future<void> _saveProduct() async {
    if (_isSaving || _isLookupOpen) return;

    final formIsValid = _formKey.currentState?.validate() ?? false;

    if (!formIsValid || (_expirationDate == null && !_withoutExpirationDate)) {
      setState(() {
        _errorMessage = _expirationDate == null && !_withoutExpirationDate
            ? 'Wybierz datę ważności lub zaznacz „Bez terminu”.'
            : 'Popraw zaznaczone pola.';
      });
      return;
    }

    final total = _totalQuantity;

    if (total == null || !total.isFinite || total <= 0 || total > 1000000) {
      setState(() {
        _errorMessage =
            'Łączna ilość musi być większa od 0 '
            'i nie może przekraczać 1 mln wybranych jednostek.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _errorMessage = 'Sesja wygasła. Zaloguj się ponownie.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final date = _withoutExpirationDate ? null : _expirationDate;

      final data = <String, dynamic>{
        'productName': _nameController.text.trim(),
        'category': _category,
        'packageSize': _parseNumber(_packageSizeController.text)!,
        'packageCount': _parsePackageCount(_packageCountController.text)!,
        'quantity': total,
        'unit': _unit,
        'storageLocation': _storageLocation,
        'expirationDate': date == null
            ? null
            : Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'source': 'manual',
        'status': 'active',
      };

      final catalogProduct = _catalogProduct;

      if (catalogProduct != null) {
        final imageUrl = catalogProduct.imageUrl?.trim();
        final barcode = catalogProduct.barcode.trim();

        final validBarcode = RegExp(
          r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$',
        ).hasMatch(barcode);

        final validImageUrl =
            imageUrl != null &&
            imageUrl.length <= 2048 &&
            RegExp(
              r'^https://images[.]openfoodfacts[.]org/images/products/[^?#]+$',
            ).hasMatch(imageUrl);

        final imageUri = imageUrl == null ? null : Uri.tryParse(imageUrl);

        final validImageHost =
            imageUri != null &&
            imageUri.scheme == 'https' &&
            imageUri.host == 'images.openfoodfacts.org' &&
            imageUri.userInfo.isEmpty &&
            !imageUri.hasPort &&
            !imageUri.hasQuery &&
            !imageUri.hasFragment;

        if (validBarcode && validImageUrl && validImageHost) {
          data.addAll({
            'imageUrl': imageUrl,
            'imageSource': 'open_food_facts',
            'imageSourceUrl':
                'https://world.openfoodfacts.org/product/$barcode',
          });
        }
      }

      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('pantry_items')
          .add(data);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        switch (error.code) {
          case 'permission-denied':
            _errorMessage =
                'Brak uprawnień do zapisu. Sprawdź aktualne reguły '
                'Firestore i przypisanie do domu.';
            break;
          case 'unavailable':
            _errorMessage = 'Baza jest chwilowo niedostępna. Sprawdź internet.';
            break;
          default:
            _errorMessage =
                'Nie udało się zapisać produktu. Kod: ${error.code}';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Wystąpił nieoczekiwany błąd. Spróbuj ponownie.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    Key? fieldKey,
  }) {
    return DropdownButtonFormField<String>(
      key: fieldKey,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.map((option) {
        return DropdownMenuItem<String>(value: option, child: Text(option));
      }).toList(),
      onChanged: _isSaving || _isLookupOpen
          ? null
          : (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
    );
  }

  Widget _buildPackagingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _packageSizeController,
                enabled: !_isSaving && !_isLookupOpen,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Wielkość opakowania',
                  hintText: 'np. 400',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final size = _parseNumber(value);

                  if (size == null ||
                      !size.isFinite ||
                      size <= 0 ||
                      size > 1000000) {
                    return 'Podaj wartość większą od 0, maks. 1 mln.';
                  }

                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown(
                fieldKey: ValueKey('package-unit-$_unit'),
                label: 'Jednostka',
                value: _unit,
                options: _units,
                onChanged: (value) {
                  setState(() {
                    _unit = value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _packageCountController,
          enabled: !_isSaving && !_isLookupOpen,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Liczba opakowań',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final count = _parsePackageCount(value);

            if (count == null || count < 1 || count > 1000000) {
              return 'Podaj całkowitą liczbę od 1 do 1 mln.';
            }

            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialEntryPending) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final catalogProduct = _catalogProduct;

    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Dodaj produkt')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSaving || _isLookupOpen
                          ? null
                          : _lookupProduct,
                      icon: const Icon(Icons.barcode_reader),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Wyszukaj po kodzie'),
                      ),
                    ),
                    if (catalogProduct != null) ...[
                      const SizedBox(height: 16),
                      _buildCatalogPreview(catalogProduct),
                    ],
                    if (_lookupMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _lookupMessage!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving && !_isLookupOpen,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa produktu',
                        hintText: 'np. Jogurt grecki (Krasnystaw)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';

                        if (name.isEmpty) {
                          return 'Wpisz nazwę produktu.';
                        }

                        if (name.length > 120) {
                          return 'Maksymalnie 120 znaków.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPackagingFields(),
                    const SizedBox(height: 20),
                    _dropdown(
                      fieldKey: ValueKey('product-category-$_category'),
                      label: 'Kategoria',
                      value: _category,
                      options: _categories,
                      onChanged: (value) {
                        setState(() {
                          _category = value;
                          _categoryWasSelectedManually = true;
                          _suggestStorageLocation();
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      fieldKey: ValueKey('storage-location-$_storageLocation'),
                      label: 'Miejsce przechowywania',
                      value: _storageLocation,
                      options: _locations,
                      onChanged: (value) {
                        setState(() {
                          _storageLocation = value;
                          _storageLocationWasSelectedManually = true;
                        });
                      },
                    ),

                    const SizedBox(height: 20),
                    _buildExpirationDateField(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _isSaving || _isLookupOpen
                          ? null
                          : _saveProduct,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          _isSaving ? 'Zapisywanie...' : 'Zapisz produkt',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

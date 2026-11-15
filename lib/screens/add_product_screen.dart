import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/package_size.dart';
import '../services/open_food_facts_service.dart';
import 'barcode_lookup_dialog.dart';

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

  DateTime? _expirationDate;
  bool _isSaving = false;
  bool _isLookupOpen = false;

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

  @override
  void dispose() {
    _nameController.dispose();
    _packageSizeController.dispose();
    _packageCountController.dispose();
    super.dispose();
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

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  String? _suggestedName(ProductLookupResult product) {
    final name = product.productName?.trim();

    if (name == null || name.isEmpty) return null;

    final brands = product.brands?.trim();

    if (brands == null || brands.isEmpty) return name;

    // API może zwrócić kilka marek rozdzielonych przecinkami.
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

    setState(() {
      _isLookupOpen = true;
    });

    try {
      final result = await showDialog<ProductLookupResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BarcodeLookupDialog(service: _lookupService),
      );

      if (!mounted || result == null) return;

      if (result.status != ProductLookupStatus.found) {
        setState(() {
          _catalogProduct = null;
          _lookupMessage =
              'Uzupełnij produkt ręcznie. Dane formularza zachowano.';
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

      final currentName = _nameController.text.trim();
      final currentSizeText = _packageSizeController.text.trim();
      final currentSize = _parseNumber(currentSizeText);

      final wouldReplaceName =
          suggestedName != null &&
          currentName.isNotEmpty &&
          currentName != suggestedName;

      final wouldReplacePackage =
          suggestedPackage != null &&
          currentSizeText.isNotEmpty &&
          (currentSize != suggestedPackage.value ||
              _unit != suggestedPackage.unit);

      if (wouldReplaceName || wouldReplacePackage) {
        final details = <String>[
          if (suggestedName != null) 'Nazwa: $suggestedName',
          if (suggestedPackage != null)
            'Opakowanie: ${suggestedPackage.inputText} '
                '${suggestedPackage.unit}',
          if (canApplyCategory) 'Kategoria: $suggestedCategory',
        ].join('\n');

        final useSuggestion = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Użyć danych z katalogu?'),
              content: Text(
                'Część pól jest już uzupełniona.\n\n'
                '$details\n\n'
                'Użycie podpowiedzi zastąpi odpowiednie pola '
                'i podgląd produktu. Kategoria wybrana ręcznie '
                'zostanie zachowana. Liczba opakowań, miejsce '
                'i termin ważności pozostaną bez zmian.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Zachowaj obecne'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Użyj podpowiedzi'),
                ),
              ],
            );
          },
        );

        if (!mounted || useSuggestion != true) return;
      }

      final messages = <String>[];

      if (suggestedName == null) {
        messages.add(
          'Brak nazwy w katalogu — wpisz ją ręcznie. '
          'Obecnej nazwy nie zmieniono.',
        );
      } else {
        messages.add('Sprawdź i w razie potrzeby popraw nazwę.');

        if (suggestedName.length > 120) {
          messages.add(
            'Podpowiedziana nazwa przekracza 120 znaków — '
            'skróć ją przed zapisaniem.',
          );
        }
      }

      if (suggestedPackage == null) {
        messages.add(
          'Brak jednoznacznej wielkości opakowania. '
          'Sprawdź ją na etykiecie; pól wielkości i jednostki '
          'nie zmieniono.',
        );
      } else {
        messages.add(
          'Wielkość opakowania podpowiedziano z katalogu — '
          'sprawdź ją na etykiecie.',
        );
      }

      if (_categoryWasSelectedManually) {
        messages.add('Zachowano kategorię wybraną ręcznie.');
      } else if (suggestedCategory != null) {
        messages.add(
          'Podpowiedziana kategoria: $suggestedCategory. '
          'Możesz ją zmienić.',
        );
      } else {
        messages.add(
          'Brak jednoznacznej podpowiedzi kategorii — '
          'sprawdź obecny wybór.',
        );
      }

      messages.add('Liczba opakowań i termin ważności nie są pobierane z API.');

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
        }

        _catalogProduct = result;
        _lookupMessage = messages.join(' ');
        _errorMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLookupOpen = false;
        });
      }
    }
  }

  void _removeCatalogPreview() {
    setState(() {
      _catalogProduct = null;
      _lookupMessage = 'Podgląd usunięto. Dane wpisane w formularzu zachowano.';
    });
  }

  Widget _imagePlaceholder(String message) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogPreview(ProductLookupResult product) {
    final imageUrl = product.imageUrl;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Podgląd z katalogu',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Usuń podgląd bez zmiany formularza',
                  onPressed: _isSaving ? null : _removeCatalogPreview,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (imageUrl == null)
              _imagePlaceholder('Brak zdjęcia w katalogu')
            else
              SizedBox(
                width: double.infinity,
                height: 160,
                child: Image.network(
                  imageUrl,
                  key: ValueKey(imageUrl),
                  fit: BoxFit.contain,
                  semanticLabel: 'Zdjęcie opakowania z Open Food Facts',
                  headers: const {
                    'User-Agent':
                        'KuchniaPlus/1.0.0 '
                        '(Android; grzegorzloban@gmail.com)',
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;

                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text('Ładowanie zdjęcia…'),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _imagePlaceholder('Nie udało się wczytać zdjęcia');
                  },
                ),
              ),
            const SizedBox(height: 16),
            Text(
              product.productName ?? 'Brak nazwy w katalogu',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('Marka: ${product.brands ?? 'brak danych'}'),
            const SizedBox(height: 6),
            Text(
              'Opakowanie według katalogu: '
              '${product.packageQuantity ?? 'brak danych'}',
            ),
            const SizedBox(height: 6),
            Text('Kod: ${product.barcode}'),
            const SizedBox(height: 12),
            const Text(
              'Sprawdź dane na swoim opakowaniu. '
              'Termin ważności oraz liczbę posiadanych opakowań '
              'podajesz samodzielnie.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'Źródło: Open Food Facts. Dane: ODbL. '
              'Zdjęcia: CC BY-SA. Dane mogą być niepełne lub błędne. '
              'Zdjęcie i karta podglądu nie są zapisywane w spiżarni.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final selected = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 30, 12, 31),
    );

    if (!mounted || selected == null) return;

    setState(() {
      _expirationDate = selected;
      _errorMessage = null;
    });
  }

  Future<void> _saveProduct() async {
    if (_isSaving || _isLookupOpen) return;

    final formIsValid = _formKey.currentState!.validate();

    if (!formIsValid || _expirationDate == null) {
      setState(() {
        _errorMessage = _expirationDate == null
            ? 'Wybierz termin ważności produktu.'
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
      final date = _expirationDate!;

      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('pantry_items')
          .add({
            'productName': _nameController.text.trim(),
            'category': _category,
            'packageSize': _parseNumber(_packageSizeController.text)!,
            'packageCount': _parsePackageCount(_packageCountController.text)!,
            'quantity': total,
            'unit': _unit,
            'storageLocation': _storageLocation,
            'expirationDate': Timestamp.fromDate(
              DateTime(date.year, date.month, date.day),
            ),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdBy': user.uid,
            'source': 'manual',
            'status': 'active',
          });

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        switch (error.code) {
          case 'permission-denied':
            _errorMessage =
                'Brak uprawnień do zapisu. Sprawdź reguły Firestore '
                'dla opakowań i przypisanie do domu.';
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
      onChanged: _isSaving
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
                enabled: !_isSaving,
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
                  setState(() => _unit = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _packageCountController,
          enabled: !_isSaving,
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
                      enabled: !_isSaving,
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
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      label: 'Miejsce przechowywania',
                      value: _storageLocation,
                      options: _locations,
                      onChanged: (value) {
                        setState(() => _storageLocation = value);
                      },
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _chooseDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          _expirationDate == null
                              ? 'Wybierz termin ważności'
                              : 'Termin: ${_formatDate(_expirationDate!)}',
                        ),
                      ),
                    ),
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
                      onPressed: _isSaving ? null : _saveProduct,
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

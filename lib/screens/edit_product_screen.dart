import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditProductScreen extends StatefulWidget {
  final String householdId;
  final String productId;
  final Map<String, dynamic> initialData;

  const EditProductScreen({
    super.key,
    required this.householdId,
    required this.productId,
    required this.initialData,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;

  late String _category;
  late String _unit;
  late String _storageLocation;

  DateTime? _expirationDate;
  bool _isBusy = false;
  String? _errorMessage;

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

  DocumentReference<Map<String, dynamic>> get _productRef {
    return FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('pantry_items')
        .doc(widget.productId);
  }

  @override
  void initState() {
    super.initState();

    final data = widget.initialData;

    _nameController = TextEditingController(
      text: data['productName'] is String ? data['productName'] as String : '',
    );

    final quantity = data['quantity'];

    _quantityController = TextEditingController(
      text: quantity is num
          ? quantity
                .toString()
                .replaceFirst(RegExp(r'\.0$'), '')
                .replaceAll('.', ',')
          : '',
    );

    _category = _categories.contains(data['category'])
        ? data['category'] as String
        : 'Inne';

    _unit = _units.contains(data['unit']) ? data['unit'] as String : 'szt.';

    _storageLocation = _locations.contains(data['storageLocation'])
        ? data['storageLocation'] as String
        : 'Inne';

    final date = data['expirationDate'];

    if (date is Timestamp) {
      final localDate = date.toDate();
      _expirationDate = DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  double? _parseQuantity(String? value) {
    return double.tryParse((value ?? '').trim().replaceAll(',', '.'));
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _expirationDate ?? today;

    final firstDate = initialDate.isBefore(DateTime(2000))
        ? initialDate
        : DateTime(2000);

    final defaultLastDate = DateTime(today.year + 30, 12, 31);
    final lastDate = initialDate.isAfter(defaultLastDate)
        ? initialDate
        : defaultLastDate;

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (!mounted || selected == null) return;

    setState(() {
      _expirationDate = selected;
      _errorMessage = null;
    });
  }

  String _messageForError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Brak uprawnień. Sprawdź reguły Firestore '
            'i członkostwo w domu.';
      case 'not-found':
        return 'Ten produkt już nie istnieje. '
            'Wróć do spiżarni i sprawdź listę.';
      case 'unavailable':
        return 'Baza jest chwilowo niedostępna. '
            'Sprawdź połączenie z internetem.';
      default:
        return 'Nie udało się wykonać operacji. Kod: ${error.code}';
    }
  }

  Future<void> _saveProduct() async {
    if (_isBusy) return;

    final isValid = _formKey.currentState!.validate();

    if (!isValid || _expirationDate == null) {
      setState(() {
        _errorMessage = _expirationDate == null
            ? 'Wybierz termin ważności produktu.'
            : 'Popraw zaznaczone pola.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final date = _expirationDate!;

      await _productRef.update({
        'productName': _nameController.text.trim(),
        'quantity': _parseQuantity(_quantityController.text)!,
        'unit': _unit,
        'category': _category,
        'storageLocation': _storageLocation,
        'expirationDate': Timestamp.fromDate(
          DateTime(date.year, date.month, date.day),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _isBusy = false;
        _errorMessage = _messageForError(error);
      });
      return;
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isBusy = false;
        _errorMessage = 'Wystąpił nieoczekiwany błąd. Spróbuj ponownie.';
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBusy = false;
    });

    Navigator.of(context).pop('updated');
  }

  Future<void> _deleteProduct() async {
    if (_isBusy) return;

    final rawName = widget.initialData['productName'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName
        : 'Produkt bez nazwy';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Usunąć produkt?'),
          content: Text(
            'Czy na pewno chcesz usunąć „$name” ze spiżarni?\n\n'
            'Usunięcie jest trwałe i dotyczy wszystkich domowników. '
            'Niezapisane zmiany w formularzu zostaną odrzucone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Anuluj'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Usuń produkt'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      await _productRef.delete();
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _isBusy = false;
        _errorMessage = _messageForError(error);
      });
      return;
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isBusy = false;
        _errorMessage = 'Nie udało się usunąć produktu. Spróbuj ponownie.';
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBusy = false;
    });

    Navigator.of(context).pop('deleted');
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.map((option) {
        return DropdownMenuItem(value: option, child: Text(option));
      }).toList(),
      onChanged: _isBusy
          ? null
          : (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edytuj produkt')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isBusy,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa produktu',
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _quantityController,
                            enabled: !_isBusy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Ilość',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final quantity = _parseQuantity(value);

                              if (quantity == null ||
                                  !quantity.isFinite ||
                                  quantity <= 0 ||
                                  quantity > 1000000) {
                                return 'Podaj liczbę większą od 0 '
                                    'i nie większą niż 1 mln.';
                              }

                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dropdown(
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
                    const SizedBox(height: 20),
                    _dropdown(
                      label: 'Kategoria',
                      value: _category,
                      options: _categories,
                      onChanged: (value) {
                        setState(() {
                          _category = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      label: 'Miejsce przechowywania',
                      value: _storageLocation,
                      options: _locations,
                      onChanged: (value) {
                        setState(() {
                          _storageLocation = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _chooseDate,
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
                      onPressed: _isBusy ? null : _saveProduct,
                      icon: const Icon(Icons.save_outlined),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Zapisz zmiany'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _deleteProduct,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Usuń produkt'),
                      ),
                    ),
                    if (_isBusy) ...[
                      const SizedBox(height: 20),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 8),
                      const Text(
                        'Trwa operacja. Przy braku połączenia '
                        'oczekiwanie może potrwać dłużej.',
                        textAlign: TextAlign.center,
                      ),
                    ],
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

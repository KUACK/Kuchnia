import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddProductScreen extends StatefulWidget {
  final String householdId;

  const AddProductScreen({super.key, required this.householdId});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  String _category = 'Inne';
  String _unit = 'szt.';
  String _storageLocation = 'Lodówka';

  DateTime? _expirationDate;
  bool _isSaving = false;
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
    if (_isSaving) return;

    final formIsValid = _formKey.currentState!.validate();

    if (!formIsValid || _expirationDate == null) {
      setState(() {
        _errorMessage = _expirationDate == null
            ? 'Wybierz termin ważności produktu.'
            : 'Popraw zaznaczone pola.';
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
            'quantity': _parseQuantity(_quantityController.text)!,
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
                'i przypisanie do domu.';
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
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((option) => DropdownMenuItem(value: option, child: Text(option)))
          .toList(),
      onChanged: _isSaving
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
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa produktu',
                        hintText: 'np. Mleko',
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
                            enabled: !_isSaving,
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
                                return 'Podaj ilość od 0 do 1 mln, bez zera.';
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
                              setState(() => _unit = value);
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
                        setState(() => _category = value);
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

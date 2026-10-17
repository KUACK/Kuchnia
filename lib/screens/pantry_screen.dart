import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_product_screen.dart';

class PantryScreen extends StatefulWidget {
  final String householdId;
  final bool onlyExpired;

  const PantryScreen({
    super.key,
    required this.householdId,
    this.onlyExpired = false,
  });

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream;

  @override
  void initState() {
    super.initState();

    _productsStream = FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('pantry_items')
        .snapshots();
  }

  Future<void> _openAddProduct() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(householdId: widget.householdId),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produkt został zapisany w spiżarni.')),
    );
  }

  DateTime? _expirationDate(Map<String, dynamic> data) {
    final value = data['expirationDate'];

    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  String _formatQuantity(dynamic value) {
    if (value is! num) return '—';

    return value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
  }

  String _text(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }

    return fallback;
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();

    // Porównujemy daty kalendarzowe, bez godzin i zmian czasu.
    final today = DateTime.utc(now.year, now.month, now.day);
    final expiry = DateTime.utc(date.year, date.month, date.day);

    return expiry.difference(today).inDays;
  }

  Widget _buildProduct(Map<String, dynamic> data) {
    final name = _text(data['productName'], 'Produkt bez nazwy');
    final quantity = _formatQuantity(data['quantity']);
    final unit = _text(data['unit'], '');
    final category = _text(data['category'], 'Inne');
    final location = _text(data['storageLocation'], 'Nie podano');
    final date = _expirationDate(data);

    Color statusColor = Colors.grey;
    String statusText = 'Brak terminu';

    if (date != null) {
      final days = _daysUntil(date);

      if (days < 0) {
        statusColor = Colors.red;
        statusText = 'Po terminie';
      } else if (days == 0) {
        statusColor = Colors.orange;
        statusText = 'Termin dzisiaj';
      } else if (days == 1) {
        statusColor = Colors.orange;
        statusText = 'Termin jutro';
      } else if (days <= 3) {
        statusColor = Colors.orange;
        statusText = 'Termin za $days dni';
      } else {
        statusColor = Colors.green;
        statusText = 'Termin za $days dni';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$quantity $unit'),
                  const SizedBox(height: 4),
                  Text(
                    '$category • $location',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    date == null
                        ? 'Nie podano terminu ważności'
                        : 'Termin ważności: ${_formatDate(date)}',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: statusColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onlyExpired ? 'Produkty po terminie' : 'Spiżarnia'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProduct,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj produkt'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            final code = error is FirebaseException ? error.code : 'nieznany';

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nie udało się odczytać produktów.\n\n'
                  'Sprawdź internet i reguły Firestore.\n'
                  'Kod błędu: $code',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data!.docs.where((document) {
            final data = document.data();

            if (data['status'] != 'active') {
              return false;
            }

            if (!widget.onlyExpired) {
              return true;
            }

            final date = _expirationDate(data);
            return date != null && _daysUntil(date) < 0;
          }).toList();

          // Najbliższy termin na początku, brak terminu na końcu.
          products.sort((a, b) {
            final dateA = _expirationDate(a.data());
            final dateB = _expirationDate(b.data());

            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;

            return dateA.compareTo(dateB);
          });

          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.kitchen_outlined, size: 72, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      widget.onlyExpired
                          ? 'Nie masz produktów po zapisanym terminie.'
                          : 'Twoja spiżarnia jest jeszcze pusta.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.onlyExpired
                          ? 'W tym widoku pokazujemy tylko produkty po terminie.'
                          : 'Kliknij „Dodaj produkt”, aby zapisać pierwszy produkt.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _buildProduct(products[index].data());
            },
          );
        },
      ),
    );
  }
}

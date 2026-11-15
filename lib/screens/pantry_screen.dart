import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_product_screen.dart';
import 'edit_product_screen.dart';

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

  Timer? _dateTimer;

  @override
  void initState() {
    super.initState();

    _productsStream = FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('pantry_items')
        .snapshots();

    _dateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _dateTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAddProduct() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddProductScreen(householdId: widget.householdId),
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produkt został zapisany w spiżarni.')),
    );
  }

  Future<void> _openEditProduct(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EditProductScreen(
          householdId: widget.householdId,
          productId: document.id,
          initialData: document.data(),
        ),
      ),
    );

    if (!mounted || result == null) return;

    final String message;

    if (result == 'deleted') {
      message = 'Produkt został usunięty ze spiżarni.';
    } else if (result == 'updated') {
      message = 'Zmiany produktu zostały zapisane.';
    } else {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    if (value is! num || !value.isFinite) return '—';

    return value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
  }

  String _text(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();

    final today = DateTime.utc(now.year, now.month, now.day);

    final expiry = DateTime.utc(date.year, date.month, date.day);

    return expiry.difference(today).inDays;
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'Nabiał' => Icons.egg_alt_outlined,
      'Mięso i ryby' => Icons.set_meal_outlined,
      'Warzywa' => Icons.eco_outlined,
      'Owoce' => Icons.apple_outlined,
      'Pieczywo' => Icons.bakery_dining_outlined,
      'Produkty suche' => Icons.grain_outlined,
      'Napoje' => Icons.local_drink_outlined,
      _ => Icons.inventory_2_outlined,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'Nabiał' => Colors.blue,
      'Mięso i ryby' => Colors.deepOrange,
      'Warzywa' => Colors.green,
      'Owoce' => Colors.pink,
      'Pieczywo' => Colors.brown,
      'Produkty suche' => Colors.amber.shade800,
      'Napoje' => Colors.teal,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  IconData _locationIcon(String location) {
    return switch (location) {
      'Lodówka' => Icons.kitchen_outlined,
      'Zamrażarka' => Icons.ac_unit,
      'Szafka' => Icons.shelves,
      _ => Icons.place_outlined,
    };
  }

  String? _packagingLabel(Map<String, dynamic> data, String unit) {
    final size = data['packageSize'];
    final count = data['packageCount'];

    if (size is! num ||
        count is! num ||
        !size.isFinite ||
        !count.isFinite ||
        size <= 0 ||
        count <= 0 ||
        count % 1 != 0) {
      return null;
    }

    return '${_formatQuantity(count)} × '
        '${_formatQuantity(size)} $unit';
  }

  Widget _buildCategoryThumbnail(String category) {
    final color = _categoryColor(category);

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(_categoryIcon(category), size: 34, color: color),
    );
  }

  Widget _buildExpiryBadge(DateTime? date) {
    final colors = Theme.of(context).colorScheme;

    Color color = colors.onSurfaceVariant;
    String label = 'Brak terminu';
    IconData icon = Icons.event_outlined;

    if (date != null) {
      final days = _daysUntil(date);

      if (days < 0) {
        color = colors.error;
        icon = Icons.warning_amber_rounded;
        label = days == -1 ? '1 dzień po terminie' : '${-days} dni po terminie';
      } else if (days == 0) {
        color = Colors.orange.shade800;
        icon = Icons.schedule;
        label = 'Termin dzisiaj';
      } else if (days == 1) {
        color = Colors.orange.shade800;
        icon = Icons.schedule;
        label = 'Termin jutro';
      } else if (days <= 3) {
        color = Colors.orange.shade800;
        icon = Icons.schedule;
        label = 'Termin za $days dni';
      } else {
        color = colors.primary;
        label = 'Termin za $days dni';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProduct(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final colors = Theme.of(context).colorScheme;

    final name = _text(data['productName'], 'Produkt bez nazwy');

    final quantity = _formatQuantity(data['quantity']);
    final unit = _text(data['unit'], '');
    final category = _text(data['category'], 'Inne');
    final location = _text(data['storageLocation'], 'Nie podano');

    final date = _expirationDate(data);
    final packaging = _packagingLabel(data, unit);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditProduct(document),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategoryThumbnail(category),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          packaging ?? '$quantity $unit',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (packaging != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Łącznie: $quantity $unit',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          category,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: colors.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _locationIcon(location),
                    size: 17,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    date == null ? 'Brak daty' : _formatDate(date),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildExpiryBadge(date),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.onlyExpired
                  ? Icons.event_available_outlined
                  : Icons.kitchen_outlined,
              size: 72,
              color: colors.primary,
            ),
            const SizedBox(height: 20),
            Text(
              widget.onlyExpired
                  ? 'Brak produktów po terminie'
                  : 'Twoja spiżarnia jest jeszcze pusta',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.onlyExpired
                  ? 'Nie masz produktów po zapisanym terminie ważności.'
                  : 'Dodaj pierwszy produkt, skanując kod '
                        'lub uzupełniając formularz ręcznie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
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
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

              if (data['status'] != 'active') return false;

              if (!widget.onlyExpired) return true;

              final date = _expirationDate(data);

              return date != null && _daysUntil(date) < 0;
            }).toList();

            products.sort((a, b) {
              final dateA = _expirationDate(a.data());
              final dateB = _expirationDate(b.data());

              if (dateA == null && dateB == null) {
                return a.id.compareTo(b.id);
              }

              if (dateA == null) return 1;
              if (dateB == null) return -1;

              final comparison = dateA.compareTo(dateB);

              return comparison != 0 ? comparison : a.id.compareTo(b.id);
            });

            if (products.isEmpty) {
              return _buildEmptyState();
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  itemCount: products.length + 1,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Pozycje: ${products.length} · '
                          'od najbliższego terminu',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }

                    return _buildProduct(products[index - 1]);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

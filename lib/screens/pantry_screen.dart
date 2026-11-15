import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_product_screen.dart';
import 'edit_product_screen.dart';
import 'product_details_screen.dart';

class _PendingDelete {
  final DocumentReference<Map<String, dynamic>> reference;
  final Timer timer;

  const _PendingDelete(this.reference, this.timer);
}

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
  static const _undoDuration = Duration(seconds: 5);

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream;
  Timer? _dateTimer;
  bool _isBusy = false;
  ScaffoldMessengerState? _messenger;

  final Map<String, _PendingDelete> _pendingDeletes = {};

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _dateTimer?.cancel();

    final hadPending = _pendingDeletes.isNotEmpty;

    for (final pending in _pendingDeletes.values) {
      pending.timer.cancel();
      pending.reference.delete().catchError((Object _) {});
    }

    _pendingDeletes.clear();

    final messenger = _messenger;

    if (hadPending && messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.clearSnackBars();
      });
    }

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

  Future<void> _openDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ProductDetailsScreen(
          householdId: widget.householdId,
          productId: document.id,
        ),
      ),
    );

    if (!mounted || result != 'deleted') return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produkt został usunięty ze spiżarni.')),
    );
  }

  Future<void> _openEdit(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EditProductScreen(
          householdId: widget.householdId,
          productId: document.id,
          initialData: Map<String, dynamic>.from(document.data()),
        ),
      ),
    );

    if (!mounted) return;

    if (result == 'deleted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produkt został usunięty ze spiżarni.')),
      );
    } else if (result == 'updated') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zmiany produktu zostały zapisane.')),
      );
    }
  }

  void _deleteProduct(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final id = document.id;

    if (_pendingDeletes.containsKey(id)) return;

    final name = _text(document.data()['productName'], 'Produkt bez nazwy');
    final messenger = ScaffoldMessenger.of(context);

    final timer = Timer(_undoDuration, () {
      _commitDelete(id);
    });

    setState(() {
      _pendingDeletes[id] = _PendingDelete(document.reference, timer);
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Usunięto: $name'),
        duration: _undoDuration,
        action: SnackBarAction(
          label: 'Cofnij',
          onPressed: () {
            if (!mounted) return;
            _undoDelete(id);
          },
        ),
      ),
    );
  }

  void _undoDelete(String id) {
    final pending = _pendingDeletes[id];

    if (pending == null) return;

    pending.timer.cancel();

    setState(() {
      _pendingDeletes.remove(id);
    });
  }

  Future<void> _commitDelete(String id) async {
    final pending = _pendingDeletes[id];

    if (pending == null) return;

    try {
      await pending.reference.delete();

      if (!mounted) return;

      setState(() {
        _pendingDeletes.remove(id);
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _pendingDeletes.remove(id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się usunąć produktu. Kod: ${error.code}'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _pendingDeletes.remove(id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nie udało się usunąć produktu. Spróbuj ponownie.'),
        ),
      );
    }
  }

  Future<bool> _handleSwipe(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    DismissDirection direction,
  ) async {
    if (_isBusy) return false;

    _isBusy = true;

    try {
      if (direction == DismissDirection.endToStart) {
        _deleteProduct(document);
      } else if (direction == DismissDirection.startToEnd) {
        await _openEdit(document);
      }
    } finally {
      _isBusy = false;
    }

    return false;
  }

  DateTime? _expirationDate(Map<String, dynamic> data) {
    final value = data['expirationDate'];

    return value is Timestamp ? value.toDate() : null;
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

  String _quantityLabel(Map<String, dynamic> data) {
    final unit = _text(data['unit'], '');
    final size = data['packageSize'];
    final count = data['packageCount'];

    final hasPackaging =
        size is num &&
        count is num &&
        size.isFinite &&
        count.isFinite &&
        size > 0 &&
        count > 0 &&
        count % 1 == 0;

    if (hasPackaging) {
      return '${_formatQuantity(count)} × '
          '${_formatQuantity(size)} $unit';
    }

    return '${_formatQuantity(data['quantity'])} $unit'.trim();
  }

  String? _imageUrl(Map<String, dynamic> data) {
    if (data['imageSource'] != 'open_food_facts') return null;

    final value = data['imageUrl'];
    if (value is! String) return null;

    final url = value.trim();
    final uri = Uri.tryParse(url);

    if (url.length > 2048 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'images.openfoodfacts.org' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/images/products/')) {
      return null;
    }

    return url;
  }

  Widget _categoryPlaceholder(String category) {
    final color = _categoryColor(category);

    return ColoredBox(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Icon(_categoryIcon(category), color: color, size: 34),
      ),
    );
  }

  Widget _buildThumbnail(Map<String, dynamic> data, String category) {
    final imageUrl = _imageUrl(data);

    return SizedBox.square(
      dimension: 76,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: imageUrl == null
            ? _categoryPlaceholder(category)
            : ColoredBox(
                color: Colors.white,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  httpHeaders: const {
                    'User-Agent':
                        'KuchniaPlus/1.0.0 '
                        '(Android; grzegorzloban@gmail.com)',
                  },
                  placeholder: (context, url) {
                    return _categoryPlaceholder(category);
                  },
                  errorWidget: (context, url, error) {
                    return _categoryPlaceholder(category);
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildExpiry(DateTime? date) {
    final colors = Theme.of(context).colorScheme;

    Color color = colors.onSurfaceVariant;
    String label = 'Bez terminu';
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

  Widget _swipeBackground({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
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
    final category = _text(data['category'], 'Inne');
    final date = _expirationDate(data);

    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(document),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThumbnail(data, category),
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
                        const SizedBox(height: 8),
                        Text(
                          _quantityLabel(data),
                          style: Theme.of(context).textTheme.bodyMedium,
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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildExpiry(date),
                  if (date != null)
                    Text(
                      _formatDate(date),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey(document.id),
      direction: DismissDirection.horizontal,
      background: _swipeBackground(
        color: Colors.blue.shade600,
        icon: Icons.edit_outlined,
        label: 'Edytuj',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: Colors.red.shade600,
        icon: Icons.delete_outline,
        label: 'Usuń',
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) => _handleSwipe(document, direction),
      child: card,
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
              if (_pendingDeletes.containsKey(document.id)) return false;

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

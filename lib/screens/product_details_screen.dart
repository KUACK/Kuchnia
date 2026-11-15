import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'edit_product_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String householdId;
  final String productId;

  const ProductDetailsScreen({
    super.key,
    required this.householdId,
    required this.productId,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _productStream;

  bool _isEditOpen = false;

  @override
  void initState() {
    super.initState();

    _productStream = FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('pantry_items')
        .doc(widget.productId)
        .snapshots();
  }

  String _text(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  String _number(dynamic value) {
    if (value is! num || !value.isFinite) return '—';

    return value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
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

  Widget _imagePlaceholder(String category, String message) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_categoryIcon(category), size: 72, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cachedImage(String url, String category) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      httpHeaders: const {
        'User-Agent':
            'KuchniaPlus/1.0.0 '
            '(Android; grzegorzloban@gmail.com)',
      },
      placeholder: (context, imageUrl) {
        return const Center(child: CircularProgressIndicator());
      },
      errorWidget: (context, imageUrl, error) {
        return _imagePlaceholder(category, 'Nie udało się wczytać zdjęcia.');
      },
    );
  }

  Future<void> _showFullImage(String url, String category, String name) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Zdjęcie produktu'),
              leading: IconButton(
                tooltip: 'Zamknij zdjęcie',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox.expand(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Semantics(
                            image: true,
                            label: 'Zdjęcie produktu: $name',
                            child: _cachedImage(url, category),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Open Food Facts i współtwórcy · CC BY-SA\n'
                      'Rozsuń palce, aby powiększyć.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEdit(Map<String, dynamic> data) async {
    if (_isEditOpen) return;

    setState(() {
      _isEditOpen = true;
    });

    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => EditProductScreen(
            householdId: widget.householdId,
            productId: widget.productId,
            initialData: Map<String, dynamic>.from(data),
          ),
        ),
      );

      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;

      if (result == 'deleted') {
        Navigator.of(context).pop('deleted');
        return;
      }

      if (result == 'updated') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zmiany produktu zostały zapisane.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEditOpen = false;
        });
      }
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSource(Map<String, dynamic> data) {
    final sourceUrl = _text(data['imageSourceUrl'], '');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Źródło zdjęcia',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open Food Facts i współtwórcy.\n'
              'Zdjęcie udostępnione na licencji CC BY-SA. '
              'Wyświetlane bez celowej modyfikacji treści.',
            ),
            if (sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Strona produktu i informacje o źródle:'),
              const SizedBox(height: 6),
              SelectableText(sourceUrl),
            ],
            const SizedBox(height: 12),
            const SelectableText(
              'Warunki wykorzystania:\n'
              'https://world.openfoodfacts.org/terms-of-use',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(Map<String, dynamic> data) {
    final colors = Theme.of(context).colorScheme;

    final name = _text(data['productName'], 'Produkt bez nazwy');
    final category = _text(data['category'], 'Inne');
    final location = _text(data['storageLocation'], 'Nie podano');
    final unit = _text(data['unit'], '');
    final imageUrl = _imageUrl(data);

    final rawDate = data['expirationDate'];
    final date = rawDate is Timestamp ? rawDate.toDate() : null;

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 260,
                child: imageUrl == null
                    ? ColoredBox(
                        color: colors.surfaceContainerLow,
                        child: _imagePlaceholder(
                          category,
                          'Brak zdjęcia produktu',
                        ),
                      )
                    : Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: () {
                            _showFullImage(imageUrl, category, name);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Semantics(
                              image: true,
                              label: 'Zdjęcie produktu: $name',
                              child: _cachedImage(imageUrl, category),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 8),
              Text(
                'Dotknij zdjęcia, aby powiększyć',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasPackaging)
                      _infoRow(
                        Icons.inventory_2_outlined,
                        'Opakowania',
                        '${_number(count)} × ${_number(size)} $unit',
                      ),
                    _infoRow(
                      Icons.straighten_outlined,
                      'Ilość łączna',
                      '${_number(data['quantity'])} $unit'.trim(),
                    ),
                    _infoRow(
                      Icons.calendar_month_outlined,
                      'Termin ważności',
                      date == null ? 'Nie podano' : _formatDate(date),
                    ),
                    _infoRow(_categoryIcon(category), 'Kategoria', category),
                    _infoRow(
                      Icons.place_outlined,
                      'Miejsce przechowywania',
                      location,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isEditOpen ? null : () => _openEdit(data),
              icon: const Icon(Icons.edit_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Edytuj produkt'),
              ),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 24),
              _buildSource(data),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Szczegóły produktu')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _productStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              final code = error is FirebaseException ? error.code : 'nieznany';

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nie udało się odczytać produktu.\n'
                    'Kod błędu: $code',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final document = snapshot.data!;
            final data = document.data();

            if (!document.exists || data == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ten produkt nie jest już dostępny.\n'
                    'Wróć do spiżarni, aby sprawdzić listę.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return _buildDetails(data);
          },
        ),
      ),
    );
  }
}

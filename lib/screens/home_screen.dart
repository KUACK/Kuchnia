import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_product_screen.dart';
import 'pantry_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final String householdId;

  const HomeScreen({super.key, required this.householdId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _soonDays = 3;

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

  Future<void> _openPantry({bool onlyExpired = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PantryScreen(
          householdId: widget.householdId,
          onlyExpired: onlyExpired,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
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

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ta funkcja będzie dostępna później.')),
    );
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();

    final today = DateTime.utc(now.year, now.month, now.day);
    final expiry = DateTime.utc(date.year, date.month, date.day);

    return expiry.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kuchnia+',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          IconButton(
            tooltip: 'Powiadomienia — w przygotowaniu',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _showComingSoon,
          ),
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ProfileScreen(householdId: widget.householdId),
                ),
              );
            },
          ),
        ],
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

          final products = snapshot.data!.docs
              .where((document) {
                return document.data()['status'] == 'active';
              })
              .map((document) {
                return _HomeProduct.fromMap(document.data());
              })
              .toList();

          final soonCount = products.where((product) {
            final date = product.expirationDate;

            if (date == null) return false;

            final days = _daysUntil(date);

            return days >= 0 && days <= _soonDays;
          }).length;

          final expired = products.where((product) {
            final date = product.expirationDate;

            return date != null && _daysUntil(date) < 0;
          }).toList();

          final upcoming = products.where((product) {
            final date = product.expirationDate;

            return date != null && _daysUntil(date) >= 0;
          }).toList();

          upcoming.sort(
            (a, b) => a.expirationDate!.compareTo(b.expirationDate!),
          );

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatsRow(
                    total: products.length,
                    expiring: soonCount,
                    expired: expired.length,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildExpiringPreview(upcoming)),
                  const SizedBox(height: 12),
                  _buildPantryTile(),
                  const SizedBox(height: 8),
                  _buildBottomButtons(),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            _openPantry();
          } else if (index != 0) {
            _showComingSoon();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: 'Spiżarnia',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'Lista zakupów',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Przepisy',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow({
    required int total,
    required int expiring,
    required int expired,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatCard(
          value: '$expiring',
          label: 'blisko terminu',
          icon: Icons.access_time,
          color: Colors.orange,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          value: '$total',
          label: 'w spiżarni',
          icon: Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _openPantry(),
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          value: '$expired',
          label: 'po terminie',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          onTap: () => _openPantry(onlyExpired: true),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Icon(icon, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showComingSoon,
            icon: const Icon(Icons.restaurant_menu_outlined),
            label: const Text('Przepisy'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showComingSoon,
            icon: const Icon(Icons.shopping_basket_outlined),
            label: const Text('Lista zakupów'),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiringPreview(List<_HomeProduct> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Najbliższe terminy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.access_time, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'Brak produktów z terminem ważności.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;

                        final rowHeight =
                            76.0 * (textScale > 1 ? textScale : 1);

                        final visibleCount = (constraints.maxHeight / rowHeight)
                            .floor()
                            .clamp(0, items.length)
                            .toInt();

                        if (visibleCount == 0) {
                          return Center(
                            child: Text(
                              'Produkty z terminem: ${items.length}. '
                              'Zobacz je w spiżarni.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: items
                              .take(visibleCount)
                              .map(
                                (product) => SizedBox(
                                  height: rowHeight,
                                  child: _buildExpiringRow(product),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(_HomeProduct product, bool isSoon) {
    final colors = Theme.of(context).colorScheme;
    final color = isSoon ? Colors.red : colors.primary;
    final imageUrl = product.imageUrl;

    final placeholder = ColoredBox(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Icon(Icons.inventory_2_outlined, color: color, size: 26),
      ),
    );

    return SizedBox.square(
      dimension: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageUrl == null
            ? placeholder
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
                  placeholder: (context, url) => placeholder,
                  errorWidget: (context, url, error) => placeholder,
                ),
              ),
      ),
    );
  }

  Widget _buildExpiringRow(_HomeProduct product) {
    final colors = Theme.of(context).colorScheme;
    final days = _daysUntil(product.expirationDate!);
    final isSoon = days <= _soonDays;

    final String label;

    if (days == 0) {
      label = 'Termin dzisiaj';
    } else if (days == 1) {
      label = 'Termin jutro';
    } else {
      label = 'Termin za $days dni';
    }

    final Color dateColor = isSoon ? Colors.red : colors.onSurfaceVariant;

    return Row(
      children: [
        _buildThumbnail(product, isSoon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                product.quantityLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dateColor,
                  fontWeight: isSoon ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPantryTile() {
    return Card(
      child: ListTile(
        onTap: () => _openPantry(),
        leading: const Icon(Icons.grid_view_outlined),
        title: const Text(
          'Spiżarnia',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Zobacz wszystkie produkty'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _openAddProduct,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openPantry(),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Usuń / Edytuj'),
          ),
        ),
      ],
    );
  }
}

class _HomeProduct {
  final String name;
  final num? quantity;
  final String unit;
  final DateTime? expirationDate;
  final String? imageUrl;

  const _HomeProduct({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.expirationDate,
    required this.imageUrl,
  });

  factory _HomeProduct.fromMap(Map<String, dynamic> data) {
    final rawName = data['productName'];
    final rawQuantity = data['quantity'];
    final rawUnit = data['unit'];
    final rawDate = data['expirationDate'];

    return _HomeProduct(
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName
          : 'Produkt bez nazwy',
      quantity: rawQuantity is num ? rawQuantity : null,
      unit: rawUnit is String ? rawUnit : '',
      expirationDate: rawDate is Timestamp ? rawDate.toDate() : null,
      imageUrl: _safeImageUrl(data),
    );
  }

  static String? _safeImageUrl(Map<String, dynamic> data) {
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

  String get quantityLabel {
    final value = quantity;

    if (value == null) return 'Nie podano ilości';

    final formatted = value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');

    return '$formatted $unit'.trim();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/open_food_facts_service.dart';
import 'barcode_scanner_screen.dart';

class BarcodeLookupDialog extends StatefulWidget {
  final OpenFoodFactsService service;

  const BarcodeLookupDialog({super.key, required this.service});

  @override
  State<BarcodeLookupDialog> createState() => _BarcodeLookupDialogState();
}

class _BarcodeLookupDialogState extends State<BarcodeLookupDialog> {
  final _controller = TextEditingController();

  bool _isSearching = false;
  bool _isScannerOpen = false;
  String? _message;

  bool get _isBusy => _isSearching || _isScannerOpen;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    if (_isBusy) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isScannerOpen = true;
      _message = null;
    });

    try {
      final code = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const BarcodeScannerScreen()),
      );

      if (!mounted || code == null || code.isEmpty) return;

      setState(() {
        _controller.text = code;
        _controller.selection = TextSelection.collapsed(offset: code.length);
        _message =
            'Kod odczytany. Naciśnij „Szukaj”, '
            'aby pobrać dane produktu.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScannerOpen = false;
        });
      }
    }
  }

  Future<void> _search() async {
    if (_isBusy) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _message = null;
    });

    final result = await widget.service.findByBarcode(_controller.text);

    if (!mounted) return;

    if (result.status == ProductLookupStatus.found) {
      Navigator.of(context).pop<ProductLookupResult>(result);
      return;
    }

    setState(() {
      _isSearching = false;
      _message = switch (result.status) {
        ProductLookupStatus.notFound =>
          'Nie znaleziono produktu. Możesz przejść '
              'do ręcznego formularza.',
        ProductLookupStatus.invalidBarcode =>
          'Wpisz kod zawierający 8, 12, 13 lub 14 cyfr.',
        ProductLookupStatus.timeout =>
          'Przekroczono czas oczekiwania. Spróbuj ponownie '
              'lub przejdź do ręcznego formularza.',
        ProductLookupStatus.networkError =>
          'Nie udało się połączyć z katalogiem. Sprawdź internet '
              'lub przejdź do ręcznego formularza.',
        ProductLookupStatus.rateLimited =>
          'Odczekaj chwilę przed kolejną próbą. Jeśli komunikat '
              'się powtarza, spróbuj ponownie za minutę.',
        ProductLookupStatus.serverError =>
          'Katalog jest chwilowo niedostępny. '
              'Możesz dodać produkt ręcznie.',
        ProductLookupStatus.invalidResponse =>
          'Nie udało się odczytać danych produktu. '
              'Możesz dodać go ręcznie.',
        ProductLookupStatus.found => null,
      };
    });
  }

  void _continueManually() {
    if (_isBusy) return;

    Navigator.of(context).pop<ProductLookupResult>(
      ProductLookupResult(
        status: ProductLookupStatus.notFound,
        barcode: _controller.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy,
      child: AlertDialog(
        title: const Text('Wyszukaj po kodzie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Zeskanuj kod aparatem albo wpisz numer '
                'spod kodu kreskowego na opakowaniu.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _openScanner,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Skanuj aparatem'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_isBusy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(14),
                ],
                decoration: const InputDecoration(
                  labelText: 'Kod kreskowy',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Źródło podpowiedzi: Open Food Facts (ODbL). '
                'Dane mogą być niepełne lub błędne — sprawdź je '
                'przed zapisaniem produktu.',
                style: TextStyle(fontSize: 12),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
              if (_isSearching) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Text(
                  'Wyszukiwanie produktu…',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: _isBusy ? null : _continueManually,
            child: const Text('Dodaj ręcznie'),
          ),
          FilledButton(
            onPressed: _isBusy ? null : _search,
            child: const Text('Szukaj'),
          ),
        ],
      ),
    );
  }
}

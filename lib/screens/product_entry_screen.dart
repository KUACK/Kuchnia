import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/open_food_facts_service.dart';

class ProductEntryScreen extends StatefulWidget {
  final OpenFoodFactsService service;

  const ProductEntryScreen({super.key, required this.service});

  @override
  State<ProductEntryScreen> createState() => _ProductEntryScreenState();
}

class _ProductEntryScreenState extends State<ProductEntryScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
    ],
    returnImage: false,
  );

  bool _isBusy = false;
  bool _isLeaving = false;
  bool _manualDialogOpen = false;
  bool _scanEnabled = true;

  int _tapCount = 0;
  DateTime? _lastTapAt;
  String? _message;

  bool get _controlsBlocked => _isBusy || _isLeaving || _manualDialogOpen;

  Future<void> _stopCamera() async {
    try {
      await _cameraController.stop();
    } catch (_) {
      // Pozostaje blokada logiczna odczytów.
    }
  }

  Future<void> _startCamera() async {
    if (!mounted || _isLeaving) return;

    try {
      await _cameraController.start();
    } catch (_) {
      // Błąd aparatu pokazuje MobileScanner.errorBuilder.
    }
  }

  Future<void> _disposeCamera() async {
    try {
      await _cameraController.dispose();
    } catch (_) {
      // Ekran jest już zamykany.
    }
  }

  @override
  void dispose() {
    unawaited(_disposeCamera());
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (!mounted || !_scanEnabled || _controlsBlocked) return;

    final codes = <String>{};

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value == null) continue;

      if (RegExp(r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13})$').hasMatch(value)) {
        codes.add(value);
      }
    }

    if (codes.length != 1) return;

    unawaited(_search(codes.single));
  }

  Future<void> _finish(ProductLookupResult result) async {
    if (!mounted || _isLeaving) return;

    setState(() {
      _isLeaving = true;
      _scanEnabled = false;
    });

    await _stopCamera();

    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    Navigator.of(context).pop<ProductLookupResult>(result);
  }

  Future<void> _search(String input) async {
    if (!mounted || _controlsBlocked) return;

    final code = input.trim();

    setState(() {
      _isBusy = true;
      _scanEnabled = false;
      _message = null;
    });

    await _stopCamera();

    if (!mounted) return;

    ProductLookupResult result;

    try {
      result = await widget.service.findByBarcode(code);
    } catch (_) {
      result = ProductLookupResult(
        status: ProductLookupStatus.networkError,
        barcode: code,
      );
    }

    if (!mounted || _isLeaving) return;

    if (result.status == ProductLookupStatus.found ||
        result.status == ProductLookupStatus.notFound) {
      await _finish(result);
      return;
    }

    setState(() {
      _isBusy = false;
      _message = switch (result.status) {
        ProductLookupStatus.invalidBarcode =>
          'Nieprawidłowy kod. Wpisz 8, 12, 13 lub 14 cyfr.',
        ProductLookupStatus.timeout =>
          'Przekroczono czas oczekiwania na katalog.',
        ProductLookupStatus.networkError =>
          'Nie udało się połączyć z katalogiem. Sprawdź internet.',
        ProductLookupStatus.rateLimited =>
          'Odczekaj chwilę przed kolejną próbą. '
              'Jeśli problem się powtarza, spróbuj za minutę.',
        ProductLookupStatus.serverError => 'Katalog jest chwilowo niedostępny.',
        ProductLookupStatus.invalidResponse =>
          'Nie udało się odczytać odpowiedzi katalogu.',
        ProductLookupStatus.found => null,
        ProductLookupStatus.notFound => null,
      };
    });

    // Po błędzie nie wznawiamy odczytów automatycznie,
    // żeby kamera nie wysyłała kolejnych zapytań o ten sam kod.
  }

  Future<void> _retryScanning() async {
    if (_controlsBlocked) return;

    setState(() {
      _isBusy = true;
      _message = null;
      _scanEnabled = false;
    });

    await _startCamera();

    if (!mounted || _isLeaving) return;

    setState(() {
      _isBusy = false;
      _scanEnabled = true;
    });
  }

  void _handleTopTap() {
    if (_controlsBlocked) return;

    final now = DateTime.now();
    final lastTap = _lastTapAt;

    if (lastTap == null ||
        now.difference(lastTap) > const Duration(milliseconds: 650)) {
      _tapCount = 0;
    }

    _lastTapAt = now;
    _tapCount++;

    if (_tapCount == 3) {
      _tapCount = 0;
      _lastTapAt = null;
      unawaited(_openManualCodeDialog());
    }
  }

  Future<void> _openManualCodeDialog() async {
    if (_controlsBlocked) return;

    final resumeScanning = _scanEnabled;

    setState(() {
      _manualDialogOpen = true;
      _scanEnabled = false;
    });

    await _stopCamera();

    if (!mounted) return;

    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualBarcodeDialog(),
    );

    if (!mounted) return;

    setState(() {
      _manualDialogOpen = false;
    });

    if (code != null) {
      await _search(code);
      return;
    }

    if (resumeScanning) {
      await _startCamera();

      if (!mounted || _isLeaving) return;

      setState(() {
        _scanEnabled = true;
      });
    }
  }

  Future<void> _continueManually() async {
    if (_controlsBlocked) return;

    await _finish(
      const ProductLookupResult(
        status: ProductLookupStatus.notFound,
        barcode: '',
      ),
    );
  }

  Widget _buildCameraError() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 40,
              ),
              SizedBox(height: 12),
              Text(
                'Nie udało się uruchomić aparatu.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'Sprawdź uprawnienie w ustawieniach aplikacji '
                'lub dodaj produkt ręcznie.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCamera(double size) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _cameraController,
              useAppLifecycleState: true,
              fit: BoxFit.cover,
              onDetect: _handleDetection,
              errorBuilder: (context, error) => _buildCameraError(),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.primary, width: 3),
                ),
              ),
            ),
            if (_isBusy)
              const ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Proszę czekać…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isLeaving,
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          title: const Text('Dodaj produkt'),
          backgroundColor: colors.surface,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cameraSize = math.min(
                340.0,
                math.min(
                  math.max(0.0, constraints.maxWidth - 48),
                  constraints.maxHeight * 0.48,
                ),
              );

              final topSpace = math.max(72.0, constraints.maxHeight * 0.13);

              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _handleTopTap,
                          child: SizedBox(height: topSpace),
                        ),
                        Center(child: _buildCamera(cameraSize)),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _isBusy
                                ? 'Wyszukiwanie produktu…'
                                : 'Umieść jeden kod kreskowy w ramce',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: _controlsBlocked
                                  ? null
                                  : _retryScanning,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Spróbuj ponownie'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: OutlinedButton.icon(
                            onPressed: _controlsBlocked
                                ? null
                                : _continueManually,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text('Dodaj produkt ręcznie'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;

    Navigator.of(context).pop<String>(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wpisz kod kreskowy'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
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
          validator: (value) {
            final code = (value ?? '').trim();

            if (!RegExp(
              r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$',
            ).hasMatch(code)) {
              return 'Wpisz 8, 12, 13 lub 14 cyfr.';
            }

            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Wyszukaj')),
      ],
    );
  }
}

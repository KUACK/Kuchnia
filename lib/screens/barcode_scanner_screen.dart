import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
    ],
    returnImage: false,
  );

  bool _isFinishing = false;

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (!mounted || _isFinishing) return;

    // Nie wybieramy automatycznie produktu, jeżeli w kadrze
    // rozpoznano kilka różnych, obsługiwanych numerów.
    final codes = <String>{};

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value == null) continue;

      if (RegExp(r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13})$').hasMatch(value)) {
        codes.add(value);
      }
    }

    if (codes.length != 1) return;

    // Blokada musi zostać ustawiona przed pierwszym await.
    setState(() {
      _isFinishing = true;
    });

    final code = codes.single;

    try {
      await _controller.stop();
    } catch (_) {
      // Nawet gdy zatrzymanie zgłosi błąd, nie obsługujemy
      // kolejnych odczytów. Kontroler zwolnimy w dispose.
    }

    if (!mounted) return;

    // Nie zamykamy innej trasy, gdy użytkownik zdążył wyjść.
    if (ModalRoute.of(context)?.isCurrent != true) return;

    Navigator.of(context).pop<String>(code);
  }

  Future<void> _releaseController() async {
    try {
      await _controller.dispose();
    } catch (_) {
      // Ekran jest już zamykany.
    }
  }

  @override
  void dispose() {
    unawaited(_releaseController());
    super.dispose();
  }

  Widget _buildCameraError() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Nie udało się uruchomić aparatu.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 12),
              Text(
                'Sprawdź uprawnienie do aparatu w ustawieniach '
                'aplikacji. Możesz też wrócić i wpisać kod ręcznie.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zeskanuj kod')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Skieruj tylny aparat na jeden kod kreskowy. '
                'Cały kod powinien być widoczny i dobrze oświetlony.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                useAppLifecycleState: true,
                onDetect: (capture) {
                  unawaited(_handleDetection(capture));
                },
                errorBuilder: (context, error) {
                  return _buildCameraError();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isFinishing
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Wróć do wpisywania kodu'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

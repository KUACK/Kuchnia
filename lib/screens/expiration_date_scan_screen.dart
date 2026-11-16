import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../services/expiration_date_parser.dart';

enum _ScanPhase { capturing, recognizing, result, error }

class ExpirationDateScanScreen extends StatefulWidget {
  const ExpirationDateScanScreen({super.key});

  @override
  State<ExpirationDateScanScreen> createState() =>
      _ExpirationDateScanScreenState();
}

class _ExpirationDateScanScreenState extends State<ExpirationDateScanScreen> {
  final ImagePicker _picker = ImagePicker();

  _ScanPhase _phase = _ScanPhase.capturing;
  bool _hasResult = false;
  bool _isWorking = false;

  String _recognizedText = '';
  List<DateCandidate> _candidates = const [];
  DateCandidate? _selected;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _captureAndRecognize();
    });
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  String _contextLabel(DateContext context) {
    return switch (context) {
      DateContext.expiry => 'Wygląda na termin ważności',
      DateContext.production => 'Wygląda na datę produkcji',
      DateContext.unknown => 'Data bez opisu',
    };
  }

  bool _isBeforeToday(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return date.isBefore(today);
  }

  Future<void> _captureAndRecognize() async {
    if (_isWorking) return;

    _isWorking = true;

    setState(() {
      _phase = _ScanPhase.capturing;
      _errorMessage = null;
    });

    TextRecognizer? recognizer;

    try {
      final photo = await _picker.pickImage(source: ImageSource.camera);

      if (!mounted) return;

      if (photo == null) {
        if (_hasResult) {
          setState(() {
            _phase = _ScanPhase.result;
          });
        } else {
          Navigator.of(context).pop();
        }

        return;
      }

      setState(() {
        _phase = _ScanPhase.recognizing;
      });

      recognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );

      if (!mounted) return;

      final candidates = ExpirationDateParser.parse(recognized.text);

      setState(() {
        _recognizedText = recognized.text;
        _candidates = candidates;
        _selected = ExpirationDateParser.suggest(candidates);
        _hasResult = true;
        _phase = _ScanPhase.result;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.code.contains('denied')
            ? 'Brak dostępu do aparatu. Zezwól na jego użycie '
                  'w ustawieniach aplikacji.'
            : 'Nie udało się zrobić zdjęcia. Spróbuj ponownie.';
        _phase = _ScanPhase.error;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Nie udało się odczytać zdjęcia. Spróbuj ponownie '
            'albo wybierz datę ręcznie.';
        _phase = _ScanPhase.error;
      });
    } finally {
      await recognizer?.close();
      _isWorking = false;
    }
  }

  Widget _buildLoader(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _errorMessage ?? 'Wystąpił błąd.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _captureAndRecognize,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Spróbuj ponownie'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Wybierz datę ręcznie'),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidate(DateCandidate candidate) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = _selected?.date == candidate.date;
    final isPast = _isBeforeToday(candidate.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isSelected
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () {
            setState(() {
              _selected = candidate;
            });
          },
          leading: Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(
            _formatDate(candidate.date),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            isPast
                ? '${_contextLabel(candidate.context)}\n'
                      'Ta data jest wcześniejsza niż dzisiaj.'
                : _contextLabel(candidate.context),
          ),
          isThreeLine: isPast,
        ),
      ),
    );
  }

  Widget _buildResult() {
    final hasCandidates = _candidates.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (hasCandidates) ...[
          Text(
            _selected == null
                ? 'Znaleziono kilka dat. Wybierz tę, która jest '
                      'terminem ważności.'
                : 'Sprawdź datę z opakowaniem i zatwierdź.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          ..._candidates.map(_buildCandidate),
        ] else
          Text(
            'Nie znaleziono pełnej daty, np. 24.11.2026. '
            'Zrób wyraźniejsze zdjęcie z bliska albo wybierz datę ręcznie.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Rozpoznany tekst'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _recognizedText.trim().isEmpty
                    ? '(nie rozpoznano tekstu)'
                    : _recognizedText,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        const SizedBox(height: 16),
        if (hasCandidates)
          FilledButton.icon(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected!.date),
            icon: const Icon(Icons.check),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Użyj daty'),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _captureAndRecognize,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Zrób zdjęcie ponownie'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _ScanPhase.capturing => _buildLoader('Otwieranie aparatu…'),
      _ScanPhase.recognizing => _buildLoader('Rozpoznawanie tekstu…'),
      _ScanPhase.error => _buildError(),
      _ScanPhase.result => _buildResult(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _ScanPhase.recognizing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Odczyt daty ważności')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }
}

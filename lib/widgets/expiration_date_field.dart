import 'package:flutter/material.dart';

class ExpirationDateField extends StatelessWidget {
  final DateTime? date;
  final bool withoutExpirationDate;
  final bool enabled;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onWithoutExpirationDate;
  final VoidCallback? onScanRequested;

  const ExpirationDateField({
    super.key,
    required this.date,
    required this.withoutExpirationDate,
    required this.enabled,
    required this.onDateSelected,
    required this.onWithoutExpirationDate,
    this.onScanRequested,
  });

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  DateTime _dateAfter(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + days);
  }

  bool _matchesDays(int days) {
    final current = date;
    if (withoutExpirationDate || current == null) return false;
    final target = _dateAfter(days);
    return current.year == target.year &&
        current.month == target.month &&
        current.day == target.day;
  }

  Future<void> _chooseDate(BuildContext context) async {
    if (!enabled) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = date ?? today;
    final defaultFirstDate = DateTime(2000);
    final defaultLastDate = DateTime(today.year + 30, 12, 31);

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate.isBefore(defaultFirstDate)
          ? initialDate
          : defaultFirstDate,
      lastDate: initialDate.isAfter(defaultLastDate)
          ? initialDate
          : defaultLastDate,
    );

    if (!context.mounted || selected == null) return;
    onDateSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final currentDate = date;

    final String? selectionText = withoutExpirationDate
        ? 'Wybrano: bez terminu'
        : currentDate == null
        ? null
        : 'Termin: ${_formatDate(currentDate)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Termin ważności', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in const [3, 10, 30, 90])
              ChoiceChip(
                label: Text('+$days dni'),
                selected: _matchesDays(days),
                onSelected: enabled
                    ? (_) => onDateSelected(_dateAfter(days))
                    : null,
              ),
            ChoiceChip(
              label: const Text('Bez terminu'),
              selected: withoutExpirationDate,
              onSelected: enabled ? (_) => onWithoutExpirationDate() : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: enabled ? () => _chooseDate(context) : null,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Wybierz konkretną datę'),
          ),
        ),
        if (onScanRequested != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: enabled ? onScanRequested : null,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Odczytaj datę aparatem'),
            ),
          ),
        ],
        if (selectionText != null) ...[
          const SizedBox(height: 8),
          Text(selectionText),
        ],
      ],
    );
  }
}

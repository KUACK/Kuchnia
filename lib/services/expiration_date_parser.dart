import 'dart:math' as math;

enum DateContext { expiry, production, unknown }

class DateCandidate {
  final DateTime date;
  final String sourceText;
  final DateContext context;

  const DateCandidate({
    required this.date,
    required this.sourceText,
    required this.context,
  });
}

class _RawMatch {
  final int start;
  final int end;
  final DateTime date;

  const _RawMatch(this.start, this.end, this.date);
}

class ExpirationDateParser {
  const ExpirationDateParser._();

  static final RegExp _dmy = RegExp(
    r'(?<!\d)(\d{1,2})\s?[.\-/]\s?(\d{1,2})\s?[.\-/]\s?(\d{4})(?!\d)',
  );
  static final RegExp _ymd = RegExp(
    r'(?<!\d)(\d{4})\s?[.\-/]\s?(\d{1,2})\s?[.\-/]\s?(\d{1,2})(?!\d)',
  );
  static final RegExp _compact = RegExp(r'(?<!\d)(\d{2})(\d{2})(\d{4})(?!\d)');

  static final RegExp _expiryHint = RegExp(
    r'\b(exp|bbe|bb|best before|use by|spozyc|przydatn|wazn|termin|najlepiej)',
  );
  static final RegExp _productionHint = RegExp(
    r'\b(data prod|produkcji|prod\.|mfg|packed|manufactured|wyprodukowano|'
    r'data pak|pakowania)',
  );

  static const Map<String, String> _diacritics = {
    'ą': 'a',
    'ć': 'c',
    'ę': 'e',
    'ł': 'l',
    'ń': 'n',
    'ó': 'o',
    'ś': 's',
    'ź': 'z',
    'ż': 'z',
  };

  static String _normalize(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();

    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacritics[char] ?? char);
    }

    return buffer.toString();
  }

  static DateTime? _validDate(int year, int month, int day, int maxYear) {
    if (year < 2000 || year > maxYear) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);

    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }

    return date;
  }

  static int _lastIndex(RegExp pattern, String text) {
    var last = -1;

    for (final match in pattern.allMatches(text)) {
      last = match.start;
    }

    return last;
  }

  static int _priority(DateContext context) {
    return switch (context) {
      DateContext.expiry => 0,
      DateContext.unknown => 1,
      DateContext.production => 2,
    };
  }

  static List<DateCandidate> parse(String text, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final maxYear = reference.year + 30;
    final normalized = _normalize(text);
    final found = <_RawMatch>[];

    void collect(RegExp pattern, int dayGroup, int monthGroup, int yearGroup) {
      for (final match in pattern.allMatches(normalized)) {
        final overlaps = found.any((existing) {
          return match.start < existing.end && existing.start < match.end;
        });

        if (overlaps) continue;

        final day = int.parse(match.group(dayGroup)!);
        final month = int.parse(match.group(monthGroup)!);
        final year = int.parse(match.group(yearGroup)!);

        final date = _validDate(year, month, day, maxYear);

        if (date == null) continue;

        found.add(_RawMatch(match.start, match.end, date));
      }
    }

    collect(_dmy, 1, 2, 3);
    collect(_ymd, 3, 2, 1);
    collect(_compact, 1, 2, 3);

    final byDate = <DateTime, DateCandidate>{};

    for (final match in found) {
      final from = math.max(0, match.start - 60);
      final before = normalized.substring(from, match.start);

      final expiryIndex = _lastIndex(_expiryHint, before);
      final productionIndex = _lastIndex(_productionHint, before);

      final DateContext context;

      if (expiryIndex == -1 && productionIndex == -1) {
        context = DateContext.unknown;
      } else if (expiryIndex > productionIndex) {
        context = DateContext.expiry;
      } else {
        context = DateContext.production;
      }

      final candidate = DateCandidate(
        date: match.date,
        sourceText: normalized.substring(match.start, match.end).trim(),
        context: context,
      );

      final existing = byDate[match.date];

      if (existing == null ||
          _priority(candidate.context) < _priority(existing.context)) {
        byDate[match.date] = candidate;
      }
    }

    final result = byDate.values.toList();

    result.sort((a, b) {
      final byPriority = _priority(a.context).compareTo(_priority(b.context));

      return byPriority != 0 ? byPriority : a.date.compareTo(b.date);
    });

    return result;
  }

  static DateCandidate? suggest(List<DateCandidate> candidates) {
    final expiry = candidates
        .where((candidate) => candidate.context == DateContext.expiry)
        .toList();

    if (expiry.length == 1) return expiry.first;

    if (expiry.isEmpty &&
        candidates.length == 1 &&
        candidates.first.context != DateContext.production) {
      return candidates.first;
    }

    return null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchnia/services/expiration_date_parser.dart';

void main() {
  final now = DateTime(2026, 11, 16);

  List<DateCandidate> parse(String text) {
    return ExpirationDateParser.parse(text, now: now);
  }

  test('rozpoznaje datę z kontekstem terminu', () {
    final result = parse('Najlepiej spożyć przed: 24.11.2026');

    expect(result, hasLength(1));
    expect(result.first.date, DateTime(2026, 11, 24));
    expect(result.first.context, DateContext.expiry);
  });

  test('obsługuje różne separatory i zapis zwarty', () {
    expect(parse('24-11-2026').first.date, DateTime(2026, 11, 24));
    expect(parse('24/11/2026').first.date, DateTime(2026, 11, 24));
    expect(parse('2026-11-24').first.date, DateTime(2026, 11, 24));
    expect(parse('24112026').first.date, DateTime(2026, 11, 24));
  });

  test('bez kontekstu data jest nieznana, ale pojedyncza jest propozycją', () {
    final result = parse('24.11.2026');

    expect(result.first.context, DateContext.unknown);
    expect(ExpirationDateParser.suggest(result)?.date, DateTime(2026, 11, 24));
  });

  test('rozróżnia produkcję i termin ważności', () {
    final result = parse(
      'Data produkcji 01.10.2026\nNajlepiej spożyć przed 24.11.2026',
    );

    expect(result, hasLength(2));
    expect(result.first.date, DateTime(2026, 11, 24));
    expect(result.first.context, DateContext.expiry);
    expect(result.last.context, DateContext.production);
    expect(ExpirationDateParser.suggest(result)?.date, DateTime(2026, 11, 24));
  });

  test('sama data produkcji nie jest propozycją terminu', () {
    final result = parse('Data produkcji 01.10.2026');

    expect(result, hasLength(1));
    expect(ExpirationDateParser.suggest(result), isNull);
  });

  test('odrzuca daty niemożliwe i uwzględnia lata przestępne', () {
    expect(parse('31.02.2026'), isEmpty);
    expect(parse('29.02.2027'), isEmpty);
    expect(parse('29.02.2028'), hasLength(1));
    expect(parse('32.01.2026'), isEmpty);
    expect(parse('10.13.2026'), isEmpty);
  });

  test('nie zgaduje dat niepełnych, dwucyfrowych lat ani numerów partii', () {
    expect(parse('EXP 11.2026'), isEmpty);
    expect(parse('24.11.26'), isEmpty);
    expect(parse('L123456789'), isEmpty);
  });

  test('usuwa duplikaty', () {
    final result = parse('EXP 24.11.2026 24.11.2026');

    expect(result, hasLength(1));
  });

  test('przy kilku datach bez kontekstu nie ma automatycznej propozycji', () {
    final result = parse('24.11.2026 30.11.2026');

    expect(result, hasLength(2));
    expect(ExpirationDateParser.suggest(result), isNull);
  });

  test('data z przeszłości jest poprawna, bez błędu parsowania', () {
    final result = parse('EXP 01.01.2026');

    expect(result, hasLength(1));
    expect(result.first.date, DateTime(2026, 1, 1));
  });
}

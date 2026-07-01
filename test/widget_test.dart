import 'package:flutter_test/flutter_test.dart';
import 'package:kuchnia/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KuchniaApp());
    expect(find.text('Kuchnia+'), findsOneWidget);
  });
}

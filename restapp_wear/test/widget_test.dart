import 'package:flutter_test/flutter_test.dart';
import 'package:restapp_wear/main.dart';

void main() {
  testWidgets('RestApp renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RestApp());
    expect(find.text('RestApp'), findsOneWidget);
  });
}

import 'package:counter_animation_enhanced_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the demo page shows a counter and its shapes', (WidgetTester tester) async {
    await tester.pumpWidget(const CounterDemoApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Counting up'), findsOneWidget);
    expect(find.text('Currency, no grouping'), findsOneWidget);
    expect(find.text('Lakhs and crores'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:trace_stone/app/trace_stone_app.dart';

void main() {
  testWidgets('shows simplified main tabs', (tester) async {
    await tester.pumpWidget(const TraceStoneApp());

    expect(find.text('今日'), findsWidgets);
    expect(find.text('回顾'), findsOneWidget);
    expect(find.text('洞察'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}

// MVP smoke test: app boots to login (no session).
import 'package:cloud9_inventory_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots to sign-in', (WidgetTester tester) async {
    await tester.pumpWidget(const Cloud9App());
    // pump fixed frames (no pumpAndSettle: spinner never settles)
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Sign in'), findsOneWidget);
  });
}

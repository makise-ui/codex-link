import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ChatGPT-style themed surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: const Scaffold(body: Text('Codex Link')),
      ),
    );

    expect(find.text('Codex Link'), findsOneWidget);
  });
}

/// Fermeture du clavier par un tap dans le vide (#197).
library;

import 'package:easyrent/core/ui/keyboard/dismiss_keyboard_on_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required VoidCallback onButton}) => MaterialApp(
  builder: (context, child) => DismissKeyboardOnTap(child: child!),
  home: Scaffold(
    body: Column(
      children: [
        const TextField(key: Key('phone'), keyboardType: TextInputType.phone),
        TextButton(
          key: const Key('button'),
          onPressed: onButton,
          child: const Text('Action'),
        ),
        const Expanded(child: SizedBox.expand(key: Key('empty'))),
      ],
    ),
  ),
);

bool _hasFocus(WidgetTester tester) {
  final field = tester.widget<EditableText>(find.byType(EditableText));
  return field.focusNode.hasFocus;
}

void main() {
  testWidgets('tap dans le vide → le champ perd le focus', (tester) async {
    await tester.pumpWidget(_app(onButton: () {}));
    await tester.tap(find.byKey(const Key('phone')));
    await tester.pump();
    expect(_hasFocus(tester), isTrue);

    await tester.tap(find.byKey(const Key('empty')));
    await tester.pump();
    expect(_hasFocus(tester), isFalse);
  });

  testWidgets('tap sur un bouton → le bouton agit (geste non volé)', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(_app(onButton: () => pressed++));
    await tester.tap(find.byKey(const Key('button')));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('tap dans le champ → le focus reste', (tester) async {
    await tester.pumpWidget(_app(onButton: () {}));
    await tester.tap(find.byKey(const Key('phone')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('phone')));
    await tester.pump();
    expect(_hasFocus(tester), isTrue);
  });
}

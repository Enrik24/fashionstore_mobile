import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/widgets/primary_button.dart';
import 'package:fashionstore_mobile/core/widgets/custom_text_field.dart';

void main() {
  group('Core Widgets Tests', () {
    testWidgets('PrimaryButton displays text and triggers onPressed', (WidgetTester tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              text: 'Ingresar',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Ingresar'), findsOneWidget);
      await tester.tap(find.text('Ingresar'));
      await tester.pump();
      expect(pressed, isTrue);
    });

    testWidgets('CustomTextField renders label and responds to input', (WidgetTester tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomTextField(
              controller: controller,
              label: 'Correo Electrónico',
              hint: 'ejemplo@correo.com',
            ),
          ),
        ),
      );

      expect(find.text('Correo Electrónico'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'test@fashionstore.com');
      await tester.pump();
      expect(controller.text, 'test@fashionstore.com');
    });

    testWidgets('CustomTextField password toggle works', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomTextField(
              label: 'Contraseña',
              isPassword: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}

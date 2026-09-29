import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/widgets/star_rating.dart';

void main() {
  group('StarRating widget (CU26)', () {
    testWidgets('modo lectura muestra promedio con media estrella',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StarRating(value: 4.5)),
        ),
      );

      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_half), findsOneWidget);
    });

    testWidgets('modo edición reporta la puntuación tocada',
        (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StarRating(
              value: 3,
              editable: true,
              onChanged: (v) => selected = v,
            ),
          ),
        ),
      );

      // Tocar la quinta estrella.
      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pump();
      expect(selected, isNotNull);
    });

    testWidgets('puntuación obligatoria: sin estrellas no hay callback',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StarRating(
              value: 0,
              editable: true,
              onChanged: (_) => calls++,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
      expect(calls, 0);
    });
  });
}

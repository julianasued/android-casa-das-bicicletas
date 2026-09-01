import 'package:casa_das_bicicletas/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('o aplicativo inicia', (WidgetTester tester) async {
    await tester.pumpWidget(const CasaDasBicicletasApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Casa das Bicicletas'), findsOneWidget);
  });
}

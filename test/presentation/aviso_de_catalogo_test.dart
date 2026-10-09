/// A faixa que diz de quando é o catálogo (OFF-005, RF34).
///
/// Três situações, porque são as três que o balcão vive: com rede (nada a
/// dizer), sem rede e catálogo fresco (informa, discreto), sem rede e catálogo
/// velho (avisa, visível).
library;

import 'package:casa_das_bicicletas/presentation/sale/aviso_de_catalogo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final agora = DateTime(2026, 10, 9, 15, 0);

  Future<void> montar(
    WidgetTester tester, {
    required DateTime? atualizadoEm,
    required bool online,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvisoDeCatalogoEmCache(
              atualizadoEm: atualizadoEm,
              online: online,
              agora: agora,
            ),
          ),
        ),
      );

  testWidgets('com rede não aparece', (tester) async {
    // Com rede a busca responde do servidor: não há idade a avisar, e a faixa
    // só ocuparia altura na tela de venda.
    await montar(tester, atualizadoEm: agora.subtract(const Duration(days: 40)), online: true);

    expect(find.textContaining('Catálogo'), findsNothing);
    expect(find.textContaining('Sem rede'), findsNothing);
  });

  testWidgets('sem rede e catálogo fresco, informa a data', (tester) async {
    await montar(tester, atualizadoEm: agora.subtract(const Duration(days: 2)), online: false);

    expect(find.text('Sem rede: catálogo de 07/10/2026.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('sem rede e catálogo velho, avisa e diz o que fazer', (tester) async {
    await montar(tester, atualizadoEm: agora.subtract(const Duration(days: 12)), online: false);

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.text('Catálogo de 27/09/2026 — 12 dias sem atualizar. Confira o preço antes de fechar.'),
      findsOneWidget,
    );
  });

  testWidgets('sem catálogo nenhum, não inventa frase', (tester) async {
    // A lista vazia da busca já explica a situação.
    await montar(tester, atualizadoEm: null, online: false);

    expect(find.byType(Text), findsNothing);
  });
}

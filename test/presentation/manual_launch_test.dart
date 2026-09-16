/// O caminho principal da V1 na tela: categoria, valor, linha lançada (§6).
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  RecordingTransport comCategorias({bool vazio = false}) =>
      RecordingTransport((request) {
        if (request.url.path.contains('product-categories')) {
          if (vazio) return jsonResponse(const {'results': <Object?>[]});
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
        }
        if (request.url.path.contains('sales')) {
          return jsonResponse(saleJson(), statusCode: 201);
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Future<RecordingTransport> montar(
    WidgetTester tester, {
    RecordingTransport? transport,
  }) async {
    final http = transport ?? comCategorias();
    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: http),
        child: MaterialApp(
          home: const NewSalePage(),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return http;
  }

  /// Passo 1 digita o valor, passo 2 toca a categoria.
  Future<void> lancar(
    WidgetTester tester,
    String categoria,
    String valorEmCentavos, {
    int quantidade = 1,
  }) async {
    for (final digito in valorEmCentavos.split('')) {
      await tester.tap(find.text(digito).first);
      await tester.pump();
    }
    for (var i = 1; i < quantidade; i++) {
      await tester.tap(find.text('+'));
      await tester.pump();
    }
    await tester.tap(find.text(categoria.toUpperCase()));
    await tester.pumpAndSettle();
  }

  testWidgets('a tela abre no lançamento, não na busca', (tester) async {
    await montar(tester);

    // Passo 1 e passo 2 na tela, como na referência.
    expect(find.textContaining('PASSO 1'), findsOneWidget);
    expect(find.textContaining('PASSO 2'), findsOneWidget);
    expect(find.text('PEÇAS'), findsOneWidget);
    expect(find.text('PNEUS'), findsOneWidget);
    expect(find.text('ÓLEOS'), findsOneWidget);
    // A busca por produto não é o caminho da V1 (§6).
    expect(find.text('Produto, SKU ou código de barras'), findsNothing);
  });

  testWidgets('lançar categoria e valor entra no carrinho', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '12000');

    expect(find.text('Peças'), findsWidgets);
    expect(find.text('R\$ 120,00'), findsWidgets);
  });

  testWidgets('quantidade em branco vale 1', (tester) async {
    await montar(tester);
    await lancar(tester, 'Pneus', '35000');

    expect(find.textContaining('1 x'), findsOneWidget);
  });

  testWidgets('quantidade informada multiplica', (tester) async {
    await montar(tester);
    await lancar(tester, 'Pneus', '35000', quantidade: 2);

    expect(find.text('R\$ 700,00'), findsWidgets);
  });

  testWidgets('várias categorias somam no total', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '12000');
    await lancar(tester, 'Pneus', '35000');
    await lancar(tester, 'Óleos', '8000');

    expect(find.text('R\$ 550,00'), findsWidgets);
  });

  testWidgets('sem valor digitado a categoria não lança nada', (tester) async {
    await montar(tester);

    // Passo 2 fica apagado até haver valor: tocar nele não tem o que lançar.
    await tester.tap(find.text('PEÇAS'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nenhum item lançado'), findsWidgets);
    expect(find.textContaining('DIGITE UM VALOR'), findsOneWidget);
  });

  testWidgets('a linha lançada pode ser removida', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '12000');

    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum item lançado.'), findsOneWidget);
  });

  testWidgets('a venda manual vai ao servidor por categoria', (tester) async {
    final http = await montar(tester);
    await lancar(tester, 'Pneus', '35000');

    await finalizarVenda(tester);

    final enviada = http.requests.lastWhere(
      (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
    );
    final itens =
        ((enviada.body! as Map)['items'] as List).cast<Map<String, Object?>>();
    expect(itens.single['category'], 'PNEUS');
    expect(itens.single['unit_price'], '350.00');
  });

  testWidgets('sem categorias a tela explica, em vez de girar para sempre',
      (tester) async {
    await montar(tester, transport: comCategorias(vazio: true));

    expect(find.textContaining('Nenhuma categoria disponível'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('a busca no catálogo segue disponível pelo menu', (tester) async {
    await montar(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar produto no catálogo'));
    await tester.pumpAndSettle();

    expect(find.text('Produto, SKU ou código de barras'), findsOneWidget);
  });
}

/// Finaliza a venda: confere e confirma, como a referência pede.
Future<void> finalizarVenda(WidgetTester tester) async {
  await tester.ensureVisible(find.text('CONFERIR E FINALIZAR'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONFERIR E FINALIZAR'), warnIfMissed: false);
  await tester.pumpAndSettle();
  // O diálogo pode não ter aberto se o botão saiu da viewport no meio: nesse
  // caso, tenta de novo já com ele visível.
  if (find.text('CONFIRMAR E IMPRIMIR').evaluate().isEmpty) {
    await tester.ensureVisible(find.text('CONFERIR E FINALIZAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFERIR E FINALIZAR'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
  await tester.pumpAndSettle();
}

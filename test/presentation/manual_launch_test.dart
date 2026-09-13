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

  Future<void> lancar(
    WidgetTester tester,
    String categoria,
    String valor, {
    String? quantidade,
  }) async {
    final botao = find.widgetWithText(FilledButton, categoria.toUpperCase());
    await tester.scrollUntilVisible(botao, 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, valor);
    if (quantidade != null) {
      await tester.enterText(find.byType(TextField).at(1), quantidade);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Lançar'));
    await tester.pumpAndSettle();
  }

  testWidgets('a tela abre nas categorias, não na busca', (tester) async {
    await montar(tester);

    expect(find.text('O QUE ESTÁ VENDENDO?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'PEÇAS'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'PNEUS'), findsOneWidget);
    // A terceira pode estar abaixo da dobra: a lista constrói sob demanda.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'ÓLEOS'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(FilledButton, 'ÓLEOS'), findsOneWidget);
    // A busca por produto saiu do caminho principal (§6).
    expect(find.text('Produto, SKU ou código de barras'), findsNothing);
  });

  testWidgets('lançar categoria e valor entra no carrinho', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '120,00');

    expect(find.text('Peças'), findsWidgets);
    expect(find.text('R\$ 120,00'), findsWidgets);
  });

  testWidgets('quantidade em branco vale 1', (tester) async {
    await montar(tester);
    await lancar(tester, 'Pneus', '350,00');

    expect(find.textContaining('1 x'), findsOneWidget);
  });

  testWidgets('quantidade informada multiplica', (tester) async {
    await montar(tester);
    await lancar(tester, 'Pneus', '350,00', quantidade: '2');

    expect(find.text('R\$ 700,00'), findsWidgets);
  });

  testWidgets('várias categorias somam no total', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '120,00');
    await lancar(tester, 'Pneus', '350,00');
    await lancar(tester, 'Óleos', '80,00');

    expect(find.text('R\$ 550,00'), findsWidgets);
  });

  testWidgets('valor vazio é recusado', (tester) async {
    await montar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'PEÇAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Lançar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Informe o valor'), findsOneWidget);
  });

  testWidgets('a linha lançada pode ser removida', (tester) async {
    await montar(tester);
    await lancar(tester, 'Peças', '120,00');

    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum item lançado.'), findsOneWidget);
  });

  testWidgets('a venda manual vai ao servidor por categoria', (tester) async {
    final http = await montar(tester);
    await lancar(tester, 'Pneus', '350,00');

    await tester.ensureVisible(find.text('GERAR VENDA E IMPRIMIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GERAR VENDA E IMPRIMIR'));
    await tester.pumpAndSettle();

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

/// Cabeçalho e filtro por categoria da Nova Venda (§6 do fluxo).
///
/// O que se garante aqui é o que mudou de lugar: o menu que dá acesso às
/// ferramentas, o "sair" que encerra o turno, o filtro das categorias da RF04 e
/// — o mais importante — que descartar a venda não feche o aplicativo agora que
/// esta tela é a raiz do fluxo.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Map<String, Object?> produto({
    int id = 1,
    String nome = 'Pneu 26 Cravado',
    String categoria = 'PNEUS',
  }) =>
      {
        'id': id,
        'sku': 'PN-$id',
        'name': nome,
        'category': categoria,
        'category_name': categoria == 'PNEUS' ? 'Pneus' : 'Peças',
        'price': '120.00',
        'barcode': '789$id',
        'is_active': true,
      };

  RecordingTransport catalogo() => RecordingTransport((request) {
        if (request.url.path.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
        }
        if (request.url.path.contains('products')) {
          return jsonResponse({
            'results': [produto(), produto(id: 2, nome: 'Câmara 26')],
          });
        }
        return jsonResponse(const <String, Object?>{});
      });

  /// Monta a venda como raiz do fluxo — que é como ela fica depois do §5.
  Future<RecordingTransport> montarComoRaiz(
    WidgetTester tester, {
    RecordingTransport? transport,
  }) async {
    final http = transport ?? catalogo();
    final deps = buildTestDependencies(transport: http);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
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

  group('cabeçalho', () {
    testWidgets('traz menu, título e sair', (tester) async {
      await montarComoRaiz(tester);

      expect(find.text('NOVA VENDA'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      // O X de fechar saiu do cabeçalho: descartar mora no menu.
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('o menu abre as ferramentas do terminal', (tester) async {
      await montarComoRaiz(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Leitor de código'), findsOneWidget);
      expect(find.text('Impressora'), findsOneWidget);
      expect(find.text('Teste Elgin M10'), findsOneWidget);
    });

    testWidgets('o menu leva à ferramenta escolhida', (tester) async {
      await montarComoRaiz(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Impressora'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /impressora'), findsOneWidget);
    });

    testWidgets('sem itens, o menu não oferece descartar', (tester) async {
      await montarComoRaiz(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Leitor de código'), findsOneWidget);
      expect(find.text('Descartar esta venda'), findsNothing);
    });
  });

  group('filtro por categoria', () {
    testWidgets('mostra as categorias da RF04', (tester) async {
      await montarComoRaiz(tester);

      expect(find.widgetWithText(ChoiceChip, 'Peças'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Pneus'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Óleos'), findsOneWidget);
    });

    testWidgets('tocar na categoria filtra a busca no servidor',
        (tester) async {
      final http = await montarComoRaiz(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Pneus'));
      await tester.pumpAndSettle();

      final ultima = http.requests.lastWhere(
        (r) => r.url.path.contains('products'),
      );
      expect(ultima.url.queryParameters['category'], 'PNEUS');
    });

    testWidgets('tocar de novo na mesma categoria limpa o filtro',
        (tester) async {
      final http = await montarComoRaiz(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Pneus'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pneus'));
      await tester.pumpAndSettle();

      final ultima = http.requests.lastWhere(
        (r) => r.url.path.contains('products'),
      );
      expect(ultima.url.queryParameters.containsKey('category'), isFalse);
    });

    testWidgets('catálogo sem categorias não ocupa espaço na tela',
        (tester) async {
      await montarComoRaiz(
        tester,
        transport: RecordingTransport((request) {
          if (request.url.path.contains('product-categories')) {
            return jsonResponse(const {'results': <Object?>[]});
          }
          return jsonResponse(const {'results': <Object?>[]});
        }),
      );

      // Por nome, e não por tipo: o seletor de forma de pagamento também
      // usa ChoiceChip, e `findsNothing` por tipo passaria a medir a coisa
      // errada.
      expect(find.widgetWithText(ChoiceChip, 'Peças'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Pneus'), findsNothing);
    });
  });

  group('descarte com a venda na raiz do fluxo', () {
    testWidgets('voltar não fecha o aplicativo — zera a venda', (tester) async {
      await montarComoRaiz(tester);

      // Lança um item para haver o que descartar.
      await tester.tap(find.text('Pneu 26 Cravado').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar esta venda'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      // A tela continua de pé: sem esta garantia, `pop()` numa pilha vazia
      // encerraria o aplicativo no meio do balcão.
      expect(find.text('NOVA VENDA'), findsOneWidget);
    });
  });
}

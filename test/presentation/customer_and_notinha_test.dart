/// Cliente na venda e detalhes da notinha (§7, §8 e §11 do fluxo).
///
/// A notinha é a venda que sai da loja sem dinheiro na mão: quem responde por
/// ela é o cliente, e é por isso que o cliente é obrigatório (RF14) e que as
/// pendências aparecem antes de confirmar a escolha (D4, RF15).
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  /// Toca em algo do painel da venda, que rola: sem trazer para a tela, o
  /// toque erra em silêncio.
  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> cliente({int id = 77, String nome = 'Maria Oliveira'}) =>
      {
        'id': id,
        'name': nome,
        'document': '12345678909',
        'phone': '11999990000',
        'is_active': true,
      };

  RecordingTransport comClientes({
    List<Map<String, Object?>>? pendencias,
  }) =>
      RecordingTransport((request) {
        if (request.url.path.contains('receivables')) {
          return jsonResponse({'results': pendencias ?? const []});
        }
        if (request.url.path.contains('customers')) {
          if (request.method == 'POST') {
            return jsonResponse(cliente(id: 99, nome: 'Cliente Novo'),
                statusCode: 201);
          }
          return jsonResponse({
            'results': [cliente()],
          });
        }
        return jsonResponse(const <String, Object?>{});
      });

  Future<CustomerSelection?> abrirBusca(
    WidgetTester tester,
    RecordingTransport transport,
  ) async {
    CustomerSelection? escolhido;
    final deps = buildTestDependencies(transport: transport);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    escolhido = await Navigator.of(context).push<CustomerSelection>(
                      MaterialPageRoute(
                        builder: (_) => const CustomerPickerPage(),
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return escolhido;
  }

  group('busca de cliente (§7)', () {
    testWidgets('traz o título do §7', (tester) async {
      await abrirBusca(tester, comClientes());

      expect(find.text('BUSCAR CLIENTE'), findsOneWidget);
    });

    testWidgets('o resultado é um alvo grande', (tester) async {
      await abrirBusca(tester, comClientes());

      final tamanho = tester.getSize(
        find.ancestor(
          of: find.text('Maria Oliveira'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(tamanho.height, greaterThanOrEqualTo(72));
    });

    testWidgets('tocar mostra o cliente e o que ele deve antes de confirmar',
        (tester) async {
      await abrirBusca(
        tester,
        comClientes(pendencias: [
          {
            'id': 501,
            'sale_id': 10482,
            'original_amount': '1500.00',
            'paid_amount': '0.00',
            'pending_amount': '1500.00',
            'status': 'ABERTA',
            'created_at': '2026-08-05T14:32:00Z',
          },
        ]),
      );

      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();

      expect(find.text('Total em aberto: R\$ 1.500,00'), findsOneWidget);
      expect(find.text('USAR ESTE CLIENTE'), findsOneWidget);
    });

    testWidgets('só devolve o cliente depois de confirmar', (tester) async {
      final transport = comClientes();
      CustomerSelection? escolhido;

      final deps = buildTestDependencies(transport: transport);
      await tester.pumpWidget(
        DependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      escolhido = await Navigator.of(context).push<CustomerSelection>(
                        MaterialPageRoute(
                          builder: (_) => const CustomerPickerPage(),
                        ),
                      );
                    },
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();

      // Desistir na folha não escolhe ninguém.
      await tester.tap(find.text('Escolher outro'));
      await tester.pumpAndSettle();
      expect(escolhido, isNull);

      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USAR ESTE CLIENTE'));
      await tester.pumpAndSettle();

      expect(escolhido?.customer.name, 'Maria Oliveira');
      // As pendências vêm junto: a venda não consulta de novo.
      expect(escolhido?.receivables, isNotNull);
    });
  });

  group('cadastro de cliente (§8)', () {
    testWidgets('só o nome é obrigatório', (tester) async {
      await abrirBusca(tester, comClientes());

      await tester.tap(find.text('CADASTRAR CLIENTE'));
      await tester.pumpAndSettle();

      // O contrato do backend pede apenas o nome; inventar obrigatoriedade
      // aqui travaria o cadastro com o cliente esperando no balcão.
      // Os rótulos seguem a referência; a obrigatoriedade segue o contrato:
      // só o nome é exigido, e o telefone é opcional apesar de a referência o
      // marcar como obrigatório.
      expect(find.text('NOME'), findsOneWidget);
      expect(find.text('TELEFONE (opcional)'), findsOneWidget);
      expect(find.text('CPF / CNPJ (opcional)'), findsOneWidget);
      expect(find.text('ENDEREÇO (opcional)'), findsOneWidget);
      expect(find.text('OBSERVAÇÃO (opcional)'), findsOneWidget);
    });
  });

  group('detalhes da notinha (§11)', () {
    Future<void> montarVenda(WidgetTester tester) async {
      final deps = buildTestDependencies(
        transport: RecordingTransport((request) {
          if (request.url.path.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
          }
          return jsonResponse(const {
            'results': [
              {
                'id': 1,
                'sku': 'PN-1',
                'name': 'Pneu 26 Cravado',
                'category': 'PNEUS',
                'category_name': 'Pneus',
                'price': '120.00',
                'barcode': '7891',
                'is_active': true,
              },
            ],
          });
        }),
      );

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
    }

    testWidgets('o painel só existe quando o pagamento é notinha',
        (tester) async {
      await montarVenda(tester);

      expect(find.text('DETALHES DA NOTINHA'), findsNothing);

      await tocar(tester, find.text('NOTINHA'));

      expect(find.text('DETALHES DA NOTINHA'), findsOneWidget);
    });

    testWidgets('sem cliente, o painel cobra o cliente', (tester) async {
      await montarVenda(tester);

      await tocar(tester, find.text('NOTINHA'));

      expect(find.textContaining('obrigatório'), findsWidgets);
    });

    testWidgets('mostra composição e valor da venda', (tester) async {
      await montarVenda(tester);

      await lancarManual(tester, 'Pneus', '12000');
      await tocar(tester, find.text('NOTINHA'));

      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('Composição'), findsOneWidget);
      expect(find.text('Valor'), findsOneWidget);
    });
  });
}

/// Lança uma linha: digita o valor no teclado e toca na categoria.
///
/// É a ordem do §6 — passo 1 o valor, passo 2 o tipo. `valor` vai em centavos,
/// como o operador digita: "12000" é R$ 120,00.
Future<void> lancarManual(
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

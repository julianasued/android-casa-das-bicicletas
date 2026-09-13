/// Cliente na venda e detalhes da notinha (§7, §8 e §11 do fluxo).
///
/// A notinha é a venda que sai da loja sem dinheiro na mão: quem responde por
/// ela é o cliente, e é por isso que o cliente é obrigatório (RF14) e que as
/// pendências aparecem antes de confirmar a escolha (D4, RF15).
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
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

  Future<Customer?> abrirBusca(
    WidgetTester tester,
    RecordingTransport transport,
  ) async {
    Customer? escolhido;
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
                    escolhido = await Navigator.of(context).push<Customer>(
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
      Customer? escolhido;

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
                      escolhido = await Navigator.of(context).push<Customer>(
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

      expect(escolhido?.name, 'Maria Oliveira');
    });
  });

  group('cadastro de cliente (§8)', () {
    testWidgets('só o nome é obrigatório', (tester) async {
      await abrirBusca(tester, comClientes());

      await tester.tap(find.text('Novo cliente'));
      await tester.pumpAndSettle();

      // O contrato do backend pede apenas o nome; inventar obrigatoriedade
      // aqui travaria o cadastro com o cliente esperando no balcão.
      expect(find.text('CPF/CNPJ (opcional)'), findsOneWidget);
      expect(find.text('Telefone (opcional)'), findsOneWidget);
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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Notinha'));
      await tester.pumpAndSettle();

      expect(find.text('DETALHES DA NOTINHA'), findsOneWidget);
    });

    testWidgets('sem cliente, o painel cobra o cliente', (tester) async {
      await montarVenda(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Notinha'));
      await tester.pumpAndSettle();

      expect(find.textContaining('obrigatório'), findsWidgets);
    });

    testWidgets('mostra composição e valor da venda', (tester) async {
      await montarVenda(tester);

      await lancarManual(tester, 'Pneus', '120,00');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Notinha'));
      await tester.pumpAndSettle();

      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('Composição'), findsOneWidget);
      expect(find.text('Valor'), findsOneWidget);
    });
  });
}

/// Lança uma linha manual — o caminho principal da V1.
Future<void> lancarManual(
  WidgetTester tester,
  String categoria,
  String valor, {
  String? quantidade,
}) async {
  await tester.tap(find.widgetWithText(FilledButton, categoria.toUpperCase()));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, valor);
  if (quantidade != null) {
    await tester.enterText(find.byType(TextField).at(1), quantidade);
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Lançar'));
  await tester.pumpAndSettle();
}

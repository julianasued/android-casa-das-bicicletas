/// Etapa 7 — cliente na venda (§7 do fluxo, D4, RF14/RF15).
///
/// A venda sai sem cliente; a notinha não. E quando há cliente, o que ele já
/// deve aparece na composição — porque é ali que se decide fiar, não três
/// telas atrás.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
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

  Map<String, Object?> pendencia({
    String pendente = '1500.00',
    String status = 'ABERTA',
  }) =>
      {
        'id': 501,
        'sale_id': 10482,
        'original_amount': '1500.00',
        'paid_amount': '0.00',
        'pending_amount': pendente,
        'status': status,
        'created_at': '2026-08-05T14:32:00Z',
      };

  RecordingTransport servidor({
    List<Map<String, Object?>>? pendencias,
    bool receivablesFalha = false,
  }) =>
      RecordingTransport((request) {
        final caminho = request.url.path;
        if (caminho.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
            ],
          });
        }
        if (caminho.contains('receivables')) {
          if (receivablesFalha) {
            return errorResponse(statusCode: 500, code: 'INTERNAL_ERROR');
          }
          return jsonResponse({'results': pendencias ?? const []});
        }
        if (caminho.contains('customers')) {
          return jsonResponse(const {
            'results': [
              {
                'id': 77,
                'name': 'Maria Oliveira',
                'document': '12345678909',
                'phone': '11999990000',
                'is_active': true,
              },
            ],
          });
        }
        if (caminho.endsWith('/sales/')) {
          return jsonResponse(saleJson(), statusCode: 201);
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Future<RecordingTransport> abrirVenda(
    WidgetTester tester, {
    RecordingTransport? transport,
  }) async {
    final http = transport ?? servidor();
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

  Future<void> lancarItem(WidgetTester tester) async {
    for (final digito in '12000'.split('')) {
      await tester.tap(find.text(digito).first);
      await tester.pump();
    }
    await tester.tap(find.text('PEÇAS'));
    await tester.pumpAndSettle();
  }

  Future<void> escolherCliente(WidgetTester tester) async {
    await tester.ensureVisible(find.text('CLIENTE'));
    await tester.tap(find.text('CLIENTE'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maria Oliveira'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USAR ESTE CLIENTE'));
    await tester.pumpAndSettle();
  }

  group('cliente é opcional, menos na notinha', () {
    testWidgets('o botão diz opcional nas demais formas', (tester) async {
      await abrirVenda(tester);
      await lancarItem(tester);

      expect(find.text('(opcional)'), findsOneWidget);
    });

    testWidgets('na notinha o botão passa a dizer obrigatório',
        (tester) async {
      await abrirVenda(tester);
      await lancarItem(tester);

      await tocar(tester, find.text('NOTINHA'));

      expect(find.text('(obrigatório)'), findsOneWidget);
    });

    testWidgets('venda sem cliente continua podendo ser finalizada',
        (tester) async {
      final http = await abrirVenda(tester);
      await lancarItem(tester);

      await finalizarVenda(tester);

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      expect((venda.body! as Map).containsKey('customer_id'), isFalse);
    });

    testWidgets('notinha sem cliente não finaliza', (tester) async {
      await abrirVenda(tester);
      await lancarItem(tester);
      await tocar(tester, find.text('NOTINHA'));

      await tester.ensureVisible(find.text('CONFERIR E FINALIZAR'));
      final botao = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('CONFERIR E FINALIZAR'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(botao.onPressed, isNull);
      expect(find.textContaining('exige um cliente'), findsOneWidget);
    });
  });

  group('cliente escolhido aparece na venda', () {
    testWidgets('nome, telefone e nada em aberto', (tester) async {
      await abrirVenda(tester);
      await lancarItem(tester);
      await escolherCliente(tester);

      expect(find.text('Maria Oliveira'), findsWidgets);
      expect(find.text('11999990000'), findsOneWidget);
      expect(find.text('Nada em aberto'), findsOneWidget);
    });

    testWidgets('total em aberto quando o cliente deve', (tester) async {
      await abrirVenda(tester, transport: servidor(pendencias: [pendencia()]));
      await lancarItem(tester);
      await escolherCliente(tester);

      expect(
        find.textContaining('Total em aberto: R\$ 1.500,00'),
        findsOneWidget,
      );
    });

    testWidgets('pendência vencida é anunciada', (tester) async {
      await abrirVenda(
        tester,
        transport: servidor(pendencias: [pendencia(status: 'VENCIDA')]),
      );
      await lancarItem(tester);
      await escolherCliente(tester);

      expect(find.textContaining('VENCIDA'), findsWidgets);
    });

    testWidgets('falha na consulta não vira "não deve nada'"'"'',
        (tester) async {
      await abrirVenda(tester, transport: servidor(receivablesFalha: true));
      await lancarItem(tester);

      await tester.ensureVisible(find.text('CLIENTE'));
      await tester.tap(find.text('CLIENTE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Oliveira'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USAR ESTE CLIENTE'));
      await tester.pumpAndSettle();

      expect(find.text('Pendências não consultadas'), findsOneWidget);
      expect(find.text('Nada em aberto'), findsNothing);
    });

    testWidgets('as pendências vêm do endpoint existente', (tester) async {
      final http =
          await abrirVenda(tester, transport: servidor(pendencias: [pendencia()]));
      await lancarItem(tester);
      await escolherCliente(tester);

      expect(
        http.requests.any(
          (r) => r.url.path.contains('/customers/77/receivables/'),
        ),
        isTrue,
      );
    });

    testWidgets('o cliente escolhido vai na venda', (tester) async {
      final http = await abrirVenda(tester);
      await lancarItem(tester);
      await escolherCliente(tester);

      await finalizarVenda(tester);

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      expect((venda.body! as Map)['customer_id'], 77);
    });
  });

  group('busca', () {
    testWidgets('pesquisa por telefone usa o mesmo parâmetro do servidor',
        (tester) async {
      final http = await abrirVenda(tester);
      await lancarItem(tester);

      await tester.ensureVisible(find.text('CLIENTE'));
      await tester.tap(find.text('CLIENTE'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '11999990000');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final busca = http.requests.lastWhere(
        (r) => r.url.path.contains('customers'),
      );
      expect(busca.url.queryParameters['q'], '11999990000');
    });
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

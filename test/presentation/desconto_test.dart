/// Tela de desconto (referência tela-desconto, §10 do fluxo).
///
/// O teto de 5% (13.3) é regra do projeto, e a referência oferece atalhos de
/// 10, 15 e 20% que o servidor recusaria no envio. O que se garante aqui é que
/// a tela respeita o teto e mostra o resultado antes de aplicar.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  RecordingTransport servidor() => RecordingTransport((request) {
        if (request.url.path.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
            ],
          });
        }
        if (request.url.path.endsWith('/sales/')) {
          return jsonResponse(saleJson(), statusCode: 201);
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Finder noDialogo(String texto) =>
      find.descendant(of: find.byType(Dialog), matching: find.text(texto));

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  /// Abre a venda com R$ 100,00 lançados — número redondo para conferir conta.
  ///
  /// `centavos` vai digitado como no balcão: "10000" são R$ 100,00.
  Future<RecordingTransport> abrirComVenda(
    WidgetTester tester, {
    String centavos = '10000',
  }) async {
    final http = servidor();
    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: http),
        child: MaterialApp(
          home: const NewSalePage(),
          onGenerateRoute: (s) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('rota')),
            settings: s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final d in centavos.split('')) {
      await tester.tap(find.text(d).first);
      await tester.pump();
    }
    await tester.tap(find.text('PEÇAS'));
    await tester.pumpAndSettle();
    return http;
  }

  Future<void> abrirDesconto(WidgetTester tester) =>
      tocar(tester, find.byIcon(Icons.percent));

  group('o diálogo da referência', () {
    testWidgets('mostra subtotal, atalhos e o teclado', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      expect(find.text('DESCONTO DA VENDA'), findsOneWidget);
      expect(find.textContaining('Subtotal R\$ 100,00'), findsOneWidget);
      expect(find.text('FICA EM'), findsOneWidget);
      expect(find.text('DESCONTO RÁPIDO'), findsOneWidget);
      expect(find.text('SEM DESCONTO'), findsOneWidget);
    });

    testWidgets('os atalhos ficam todos dentro do teto de 5%', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      for (final atalho in ['1%', '2%', '3%', '5%']) {
        expect(noDialogo(atalho), findsOneWidget, reason: atalho);
      }
      // A referência traz 10, 15 e 20 — que o servidor recusaria (13.3).
      for (final proibido in ['10%', '15%', '20%']) {
        expect(noDialogo(proibido), findsNothing, reason: proibido);
      }
    });

    testWidgets('o atalho mostra quanto a venda fica', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      await tocar(tester, noDialogo('5%'));

      // 100,00 menos 5% = 95,00, calculado pelo mesmo caminho do total.
      expect(noDialogo('R\$ 95,00'), findsOneWidget);
    });

    testWidgets('digitar o percentual atualiza a prévia', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      for (final d in ['2', '0', '0']) {
        await tocar(tester, noDialogo(d));
      }

      expect(noDialogo('2%'), findsWidgets);
      expect(noDialogo('R\$ 98,00'), findsOneWidget);
    });
  });

  group('o teto de 5% (13.3)', () {
    testWidgets('acima do teto avisa e trava o aplicar', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      for (final d in ['8', '0', '0']) {
        await tocar(tester, noDialogo(d));
      }

      expect(find.text('O desconto máximo é de 5%.'), findsOneWidget);
      final aplicar = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('APLICAR DESCONTO'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(aplicar.onPressed, isNull);
    });

    testWidgets('no teto exato o aplicar libera', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));

      final aplicar = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('APLICAR DESCONTO'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(aplicar.onPressed, isNotNull);
    });
  });

  group('aplicar e remover', () {
    testWidgets('o desconto aplicado entra no total da venda', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      await tocar(tester, find.text('APLICAR DESCONTO'));

      expect(find.text('R\$ 95,00'), findsWidgets);
    });

    testWidgets('cancelar não mexe no total', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      await tocar(tester, find.text('CANCELAR'));

      expect(find.text('R\$ 100,00'), findsWidgets);
    });

    testWidgets('sem desconto volta a venda ao valor cheio', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      await tocar(tester, find.text('APLICAR DESCONTO'));
      expect(find.text('R\$ 95,00'), findsWidgets);

      await abrirDesconto(tester);
      await tocar(tester, find.text('SEM DESCONTO'));

      expect(find.text('R\$ 100,00'), findsWidgets);
    });

    testWidgets('o desconto vai ao servidor como percentual', (tester) async {
      final http = await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      await tocar(tester, find.text('APLICAR DESCONTO'));

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));
      await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
      await tester.pumpAndSettle();

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      // O contrato aceita `discount_percent`, não valor em reais.
      expect((venda.body! as Map)['discount_percent'], '5.00');
    });
  });

  /// Desconto digitado em reais.
  ///
  /// O contrato do servidor continua sendo `discount_percent`: o modo em reais
  /// só muda a unidade de entrada, converte, e daí para baixo é o caminho de
  /// sempre — mesmo teto, mesma conta, mesmo campo enviado.
  group(r'desconto em R$', () {
    Future<void> trocarParaReais(WidgetTester tester) =>
        tocar(tester, noDialogo('R\$'));

    Future<void> digitar(WidgetTester tester, String digitos) async {
      for (final d in digitos.split('')) {
        await tocar(tester, noDialogo(d));
      }
    }

    FilledButton aplicar(WidgetTester tester) => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('APLICAR DESCONTO'),
            matching: find.byType(FilledButton),
          ),
        );

    testWidgets('o diálogo oferece as duas unidades', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);

      expect(noDialogo('%'), findsOneWidget);
      expect(noDialogo('R\$'), findsOneWidget);
      expect(noDialogo('DESCONTO'), findsOneWidget);
      expect(noDialogo('EQUIVALE A'), findsOneWidget);
    });

    testWidgets('R\$ 5,00 em R\$ 100,00 viram 5%', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '500');

      // O valor digitado em cima, o percentual equivalente embaixo.
      expect(noDialogo('R\$ 5,00'), findsOneWidget);
      expect(noDialogo('5%'), findsWidgets);
      expect(noDialogo('- R\$ 5,00'), findsOneWidget);
      expect(noDialogo('R\$ 95,00'), findsOneWidget);
    });

    testWidgets('o valor em reais chega ao servidor como percentual',
        (tester) async {
      final http = await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '500');
      await tocar(tester, find.text('APLICAR DESCONTO'));

      expect(find.text('R\$ 95,00'), findsWidgets);

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));
      await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
      await tester.pumpAndSettle();

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      expect((venda.body! as Map)['discount_percent'], '5.00');
    });

    testWidgets('no teto exato em reais o aplicar libera', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '500');

      expect(find.text('O desconto máximo é de 5%.'), findsNothing);
      expect(aplicar(tester).onPressed, isNotNull);
    });

    testWidgets('valor em reais acima do teto avisa e trava', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      // R$ 6,00 em R$ 100,00 são 6%: o teto é o mesmo dos dois lados.
      await digitar(tester, '600');

      expect(find.text('O desconto máximo é de 5%.'), findsOneWidget);
      expect(noDialogo('6%'), findsOneWidget);
      expect(aplicar(tester).onPressed, isNull);
    });

    testWidgets('sem nada digitado o aplicar continua travado', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);

      expect(noDialogo('R\$ 0,00'), findsOneWidget);
      expect(aplicar(tester).onPressed, isNull);
    });

    testWidgets('trocar de unidade converte o que já está digitado',
        (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));

      await trocarParaReais(tester);
      // 5% de R$ 100,00: o número na tela muda de unidade, não de valor.
      expect(noDialogo('R\$ 5,00'), findsOneWidget);
      expect(noDialogo('R\$ 95,00'), findsOneWidget);

      await tocar(tester, noDialogo('%'));
      expect(noDialogo('5%'), findsWidgets);
      expect(noDialogo('R\$ 95,00'), findsOneWidget);
    });

    testWidgets('o atalho também vale no modo em reais', (tester) async {
      await abrirComVenda(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await tocar(tester, noDialogo('3%'));

      expect(noDialogo('R\$ 3,00'), findsOneWidget);
      expect(noDialogo('R\$ 97,00'), findsOneWidget);
    });

  });

  /// O valor em reais é a fonte de verdade, não um atalho para o percentual.
  ///
  /// R$ 1.387,93 é o caso que motivou a correção: 4,97% dão R$ 68,98 e 4,98%
  /// dão R$ 69,12. Nenhum percentual de duas casas produz R$ 69,00, então
  /// converter para calcular fazia a venda receber um número que ninguém
  /// combinou. O percentual passou a ser só exibição.
  group(r'valor em R$ que não cabe no percentual', () {
    /// Venda de R$ 1.387,93.
    Future<RecordingTransport> abrirVendaQuebrada(WidgetTester tester) =>
        abrirComVenda(tester, centavos: '138793');

    Future<void> trocarParaReais(WidgetTester tester) =>
        tocar(tester, noDialogo('R\$'));

    Future<void> digitar(WidgetTester tester, String digitos) async {
      for (final d in digitos.split('')) {
        await tocar(tester, noDialogo(d));
      }
    }

    FilledButton aplicar(WidgetTester tester) => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('APLICAR DESCONTO'),
            matching: find.byType(FilledButton),
          ),
        );

    testWidgets('R\$ 69,00 é aplicado exatamente como R\$ 69,00',
        (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '6900');

      expect(noDialogo('- R\$ 69,00'), findsOneWidget);
      // O percentual aparece, mas só como informação.
      expect(noDialogo('4,97%'), findsOneWidget);
      expect(noDialogo('R\$ 1.318,93'), findsOneWidget);
    });

    testWidgets('o total da venda recebe o valor exato', (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '6900');
      await tocar(tester, find.text('APLICAR DESCONTO'));

      // R$ 1.387,93 - R$ 69,00. Pelo caminho antigo daria R$ 1.318,95.
      expect(find.text('R\$ 1.318,93'), findsWidgets);
    });

    testWidgets('o valor negociado vai ao servidor em reais', (tester) async {
      final http = await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '6900');
      await tocar(tester, find.text('APLICAR DESCONTO'));

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));
      await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
      await tester.pumpAndSettle();

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      final corpo = venda.body! as Map;
      expect(corpo['discount_amount'], '69.00');
      // O percentual continua indo junto: é o que um servidor que ainda não
      // conhece o campo novo usaria, em vez de recusar a venda.
      expect(corpo['discount_percent'], '4.97');
    });

    testWidgets('em % a venda continua calculando pelo percentual',
        (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));

      // 5% de R$ 1.387,93 são R$ 69,3965, que fecham em R$ 69,40.
      expect(noDialogo('- R\$ 69,40'), findsOneWidget);
      expect(noDialogo('R\$ 1.318,53'), findsOneWidget);

      await tocar(tester, find.text('APLICAR DESCONTO'));
      expect(find.text('R\$ 1.318,53'), findsWidgets);
    });

    testWidgets('em % o servidor recebe percentual, não valor', (tester) async {
      final http = await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      await tocar(tester, find.text('APLICAR DESCONTO'));

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));
      await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
      await tester.pumpAndSettle();

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      final corpo = venda.body! as Map;
      expect(corpo['discount_percent'], '5.00');
      expect(corpo.containsKey('discount_amount'), isFalse);
    });

    testWidgets('no teto exato em reais o aplicar libera', (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      // O teto em reais desta venda.
      await digitar(tester, '6940');

      expect(noDialogo('- R\$ 69,40'), findsOneWidget);
      expect(find.text('O desconto máximo é de 5%.'), findsNothing);
      expect(aplicar(tester).onPressed, isNotNull);
    });

    testWidgets('um centavo acima do teto trava', (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '6941');

      // 6941 daria 5,00% se medido pelo percentual arredondado, e passaria.
      // O teto é conferido em reais justamente por isso.
      expect(find.text('O desconto máximo é de 5%.'), findsOneWidget);
      expect(aplicar(tester).onPressed, isNull);
    });

    testWidgets('trocar de % para R\$ não move o valor', (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await tocar(tester, noDialogo('5%'));
      expect(noDialogo('- R\$ 69,40'), findsOneWidget);

      await trocarParaReais(tester);
      // O mesmo R$ 69,40, agora como valor negociado.
      expect(noDialogo('- R\$ 69,40'), findsOneWidget);
      expect(noDialogo('R\$ 1.318,53'), findsOneWidget);
      expect(aplicar(tester).onPressed, isNotNull);
    });

    testWidgets('sem desconto continua zerando a venda', (tester) async {
      await abrirVendaQuebrada(tester);
      await abrirDesconto(tester);
      await trocarParaReais(tester);
      await digitar(tester, '6900');
      await tocar(tester, find.text('APLICAR DESCONTO'));
      expect(find.text('R\$ 1.318,93'), findsWidgets);

      await abrirDesconto(tester);
      await tocar(tester, find.text('SEM DESCONTO'));

      expect(find.text('R\$ 1.387,93'), findsWidgets);
    });
  });
}

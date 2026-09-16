/// Forma de pagamento e desconto na tela de venda (§9 e §10 do fluxo).
///
/// O teto de 5% é recusa deste aplicativo (13.3) e trava a venda. Crédito com
/// desconto é outra coisa: o backend aceita registrar e recusa só no caixa, e
/// por isso aqui é aviso — o botão de finalizar continua ativo.
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

    await lancarManual(tester, 'Peças', '12000');
  }

  /// Uma tecla do diálogo — escopada de propósito: o teclado da venda, atrás
  /// da barreira modal, tem as mesmas teclas, e `find.text('8').first` acertava
  /// a de trás, que não recebe toque.
  Finder teclaDoDialogo(String digito) => find.descendant(
        of: find.byType(Dialog),
        matching: find.text(digito),
      );

  /// Aplica desconto pelo diálogo da referência: abre, digita o percentual em
  /// centésimos ("500" = 5,00%) e confirma.
  Future<void> aplicarDesconto(WidgetTester tester, String centesimos) async {
    await tocar(tester, find.byIcon(Icons.percent));
    for (final digito in centesimos.split('')) {
      await tocar(tester, teclaDoDialogo(digito));
    }
    await tocar(tester, find.text('APLICAR DESCONTO'));
  }

  group('formas de pagamento (§9)', () {
    testWidgets('as cinco formas estão na tela', (tester) async {
      await montarVenda(tester);

      // A referência põe as cinco em grade, com o rótulo em caixa alta. A
      // escolhida aparece duas vezes: no botão e no cartão do total, que
      // mostra a forma da venda — também como na referência.
      for (final forma in ['PIX', 'DINHEIRO', 'CRÉDITO', 'DÉBITO', 'NOTINHA']) {
        expect(find.text(forma), findsWidgets, reason: forma);
      }
    });
  });

  group('desconto (§10)', () {
    testWidgets('acima de 5% o diálogo avisa e não deixa aplicar',
        (tester) async {
      await montarVenda(tester);
      await tocar(tester, find.byIcon(Icons.percent));

      for (final digito in '800'.split('')) {
        await tocar(tester, teclaDoDialogo(digito));
      }
      await tester.ensureVisible(find.text('O desconto máximo é de 5%.'));
      await tester.pumpAndSettle();

      expect(find.text('O desconto máximo é de 5%.'), findsOneWidget);
      final aplicar = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('APLICAR DESCONTO'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(aplicar.onPressed, isNull);
    });

    testWidgets('5% é aceito e entra no total', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '500');

      // 120,00 menos 5% = 114,00
      expect(find.text('R\$ 114,00'), findsWidgets);
    });
  });

  group('crédito com desconto (§10 / 13.3)', () {
    testWidgets('avisa que o caixa vai recusar', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '500');

      await tocar(tester, find.text('CRÉDITO'));

      expect(find.textContaining('não recebe no crédito'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('o aviso não trava a venda', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '500');
      await tocar(tester, find.text('CRÉDITO'));

      // O backend aceita registrar esta venda; travar aqui inventaria regra.
      final botao = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('CONFERIR E FINALIZAR'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('tirar o desconto tira o aviso', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '500');
      await tocar(tester, find.text('CRÉDITO'));
      expect(find.textContaining('não recebe no crédito'), findsOneWidget);

      await tocar(tester, find.byIcon(Icons.percent));
      await tocar(tester, find.text('SEM DESCONTO'));

      expect(find.textContaining('não recebe no crédito'), findsNothing);
    });

    testWidgets('sem desconto, o crédito não avisa nada', (tester) async {
      await montarVenda(tester);

      await tocar(tester, find.text('CRÉDITO'));

      expect(find.textContaining('não recebe no crédito'), findsNothing);
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

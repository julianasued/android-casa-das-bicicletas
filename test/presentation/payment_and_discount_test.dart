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

    await lancarManual(tester, 'Peças', '120,00');
  }

  Future<void> aplicarDesconto(WidgetTester tester, String percentual) async {
    await tester.tap(find.byIcon(Icons.percent));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, percentual);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
  }

  group('formas de pagamento (§9)', () {
    testWidgets('as cinco formas estão na tela', (tester) async {
      await montarVenda(tester);

      for (final forma in ['PIX', 'Dinheiro', 'Crédito', 'Débito', 'Notinha']) {
        expect(
          find.widgetWithText(ChoiceChip, forma),
          findsOneWidget,
          reason: forma,
        );
      }
    });
  });

  group('desconto (§10)', () {
    testWidgets('acima de 5% é recusado antes de ir à rede', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '8');

      expect(find.text('O desconto máximo é de 5%.'), findsOneWidget);
    });

    testWidgets('5% é aceito e entra no total', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '5');

      // 120,00 menos 5% = 114,00
      expect(find.text('R\$ 114,00'), findsWidgets);
    });
  });

  group('crédito com desconto (§10 / 13.3)', () {
    testWidgets('avisa que o caixa vai recusar', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '5');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
      await tester.pumpAndSettle();

      expect(find.textContaining('não recebe no crédito'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('o aviso não trava a venda', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '5');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
      await tester.pumpAndSettle();

      // O backend aceita registrar esta venda; travar aqui inventaria regra.
      final botao = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Finalizar e imprimir'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('tirar o desconto tira o aviso', (tester) async {
      await montarVenda(tester);
      await aplicarDesconto(tester, '5');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
      await tester.pumpAndSettle();
      expect(find.textContaining('não recebe no crédito'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.percent));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem desconto'));
      await tester.pumpAndSettle();

      expect(find.textContaining('não recebe no crédito'), findsNothing);
    });

    testWidgets('sem desconto, o crédito não avisa nada', (tester) async {
      await montarVenda(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
      await tester.pumpAndSettle();

      expect(find.textContaining('não recebe no crédito'), findsNothing);
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

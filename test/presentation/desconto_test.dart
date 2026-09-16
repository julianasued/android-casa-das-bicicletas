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
  Future<RecordingTransport> abrirComVenda(WidgetTester tester) async {
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

    for (final d in '10000'.split('')) {
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
}

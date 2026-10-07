/// Etapa 6 — montar a venda (§6 do fluxo, referência tela-nova-venda-b).
///
/// A ordem é a da referência: passo 1 digita o valor, passo 2 escolhe a
/// categoria. Enquanto não há valor, as categorias ficam apagadas — tocar nelas
/// não teria o que lançar.
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
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
        }
        if (request.url.path.endsWith('/sales/')) {
          return jsonResponse(saleJson(), statusCode: 201);
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  Future<RecordingTransport> abrir(WidgetTester tester) async {
    final http = servidor();
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-L1-001', storeId: 1);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
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
    return http;
  }

  Future<void> digitar(WidgetTester tester, String centavos) async {
    for (final d in centavos.split('')) {
      await tester.tap(find.text(d).first);
      await tester.pump();
    }
  }

  Future<void> lancar(
    WidgetTester tester,
    String categoria,
    String centavos, {
    int quantidade = 1,
  }) async {
    await digitar(tester, centavos);
    for (var i = 1; i < quantidade; i++) {
      await tester.tap(find.text('+'));
      await tester.pump();
    }
    await tester.tap(find.text(categoria));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  group('cabeçalho (§6)', () {
    testWidgets('traz menu, título, vendedor e sair', (tester) async {
      await abrir(tester);

      expect(find.text('NOVA VENDA'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      // Sem vendedor na sessão do teste, o lugar dele fica marcado.
      expect(find.text('VENDEDOR'), findsOneWidget);
    });
  });

  group('lançamento por categoria', () {
    testWidgets('as três categorias aparecem com exemplo', (tester) async {
      await abrir(tester);

      expect(find.text('PEÇAS'), findsOneWidget);
      expect(find.text('PNEUS'), findsOneWidget);
      expect(find.text('ÓLEOS'), findsOneWidget);
      expect(find.text('freios, câmaras, correntes'), findsOneWidget);
    });

    testWidgets('sem valor, o passo 2 avisa e nada é lançado', (tester) async {
      await abrir(tester);

      expect(find.textContaining('DIGITE UM VALOR'), findsOneWidget);
      await tester.tap(find.text('PNEUS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhum item lançado'), findsWidgets);
    });

    testWidgets('com valor, o passo 2 mostra o que será lançado',
        (tester) async {
      await abrir(tester);
      await digitar(tester, '35000');

      expect(find.textContaining('R\$ 350,00'), findsWidgets);
      expect(find.textContaining('O QUE É ESTE VALOR'), findsOneWidget);
    });

    testWidgets('peça, óleo e pneu somam no total', (tester) async {
      await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');
      await lancar(tester, 'ÓLEOS', '8000');
      await lancar(tester, 'PNEUS', '35000');

      expect(find.text('R\$ 550,00'), findsWidgets);
    });

    testWidgets('quantidade multiplica o valor da linha', (tester) async {
      await abrir(tester);
      await lancar(tester, 'PNEUS', '35000', quantidade: 2);

      expect(find.text('R\$ 700,00'), findsWidgets);
    });

    testWidgets('o valor volta a zero depois de lançar', (tester) async {
      await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');

      expect(find.textContaining('DIGITE UM VALOR'), findsOneWidget);
    });
  });

  group('desfazer e remover', () {
    testWidgets('desfazer tira o último lançamento', (tester) async {
      await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');

      expect(find.text('DESFAZER'), findsOneWidget);
      await tester.tap(find.text('DESFAZER'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhum item lançado'), findsWidgets);
      expect(find.text('DESFAZER'), findsNothing);
    });

    testWidgets('remover a linha tira o valor do total', (tester) async {
      await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');

      // Em tela larga a linha traz o × da referência; em tela estreita, a
      // lixeira do painel da venda. O teste roda no segundo caso.
      await tocar(tester, find.byIcon(Icons.delete_outline).last);

      expect(find.textContaining('Nenhum item lançado'), findsWidgets);
    });
  });

  group('conferência antes de imprimir', () {
    testWidgets('o botão abre a conferência, não imprime direto',
        (tester) async {
      final http = await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));

      expect(find.text('CONFIRA ANTES DE IMPRIMIR'), findsOneWidget);
      // Nada foi enviado ainda: conferir não é confirmar.
      expect(
        http.requests.any(
          (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
        ),
        isFalse,
      );
    });

    testWidgets('voltar e corrigir não envia a venda', (tester) async {
      final http = await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');
      await tocar(tester, find.text('CONFERIR E FINALIZAR'));

      await tester.tap(find.text('VOLTAR E CORRIGIR'));
      await tester.pumpAndSettle();

      expect(
        http.requests.any(
          (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
        ),
        isFalse,
      );
      // E a venda continua montada, para corrigir.
      expect(find.text('R\$ 120,00'), findsWidgets);
    });

    testWidgets('confirmar envia a venda com os itens', (tester) async {
      final http = await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');
      await lancar(tester, 'PNEUS', '35000');

      await tocar(tester, find.text('CONFERIR E FINALIZAR'));
      await tester.tap(find.text('CONFIRMAR E IMPRIMIR'));
      await tester.pumpAndSettle();

      final venda = http.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      final itens =
          ((venda.body! as Map)['items'] as List).cast<Map<String, Object?>>();
      expect(itens, hasLength(2));
      expect(itens.first['category'], 'PECAS');
      expect(itens.last['category'], 'PNEUS');
    });
  });

  group('pagamento (§9)', () {
    testWidgets('as cinco formas ficam visíveis de uma vez', (tester) async {
      await abrir(tester);

      for (final forma in ['PIX', 'DINHEIRO', 'CRÉDITO', 'DÉBITO', 'NOTINHA']) {
        expect(find.text(forma), findsWidgets, reason: forma);
      }
    });

    testWidgets('a forma escolhida aparece no cartão do total',
        (tester) async {
      await abrir(tester);
      await lancar(tester, 'PEÇAS', '12000');

      await tocar(tester, find.text('PIX'));

      // Duas vezes: o botão e o cartão do total, como na referência.
      expect(find.text('PIX'), findsNWidgets(2));
    });
  });
}

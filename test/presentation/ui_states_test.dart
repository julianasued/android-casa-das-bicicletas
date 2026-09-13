/// Estados de tela que o §18 exige, verificados onde o operador os encontra.
///
/// A regra que dá sentido a todos: nenhuma tela pode ficar parada sem dizer o
/// que houve. Girar para sempre, lista vazia sem explicação e erro engolido são
/// os três jeitos de o balcão travar sem ninguém saber por quê.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:casa_das_bicicletas/presentation/seller/seller_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_controller.dart';

import '../support/fakes.dart';

void main() {
  Future<void> montar(WidgetTester tester, Widget tela,
      RecordingTransport transport) async {
    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: transport),
        child: MaterialApp(
          home: tela,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('rota')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RecordingTransport falhando() => RecordingTransport(
        (_) => jsonResponse(
          const {
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': 'Erro não tratado.',
              'details': <String, Object?>{},
            },
          },
          statusCode: 500,
        ),
      );

  RecordingTransport vazio() =>
      RecordingTransport((_) => jsonResponse(const {'results': <Object?>[]}));

  group('erro oferece retry', () {
    testWidgets('seleção de vendedor', (tester) async {
      await montar(tester, const SellerSelectionPage(), falhando());
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('busca de cliente', (tester) async {
      await montar(tester, const CustomerPickerPage(), falhando());
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('nova venda sem categorias', (tester) async {
      await montar(tester, const NewSalePage(), falhando());
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('vazio é explicado, não deixado em branco', () {
    testWidgets('nenhum vendedor habilitado', (tester) async {
      await montar(tester, const SellerSelectionPage(), vazio());
      expect(find.textContaining('Nenhum vendedor habilitado'), findsOneWidget);
    });

    testWidgets('nenhum cliente encontrado', (tester) async {
      await montar(tester, const CustomerPickerPage(), vazio());
      expect(find.textContaining('Nenhum cliente encontrado'), findsOneWidget);
    });

    testWidgets('nenhuma categoria para lançar', (tester) async {
      await montar(tester, const NewSalePage(), vazio());
      expect(find.textContaining('Nenhuma categoria disponível'), findsOneWidget);
    });
  });

  group('nenhuma tela fica girando sem fim', () {
    // `pumpAndSettle` estoura se houver animação infinita; um indicador de
    // progresso que nunca sai é exatamente isso. Os testes acima já passariam
    // por aqui, mas o caso do catálogo vazio foi um defeito real — a venda
    // girava para sempre num terminal sem rede.
    testWidgets('venda com catálogo vazio assenta', (tester) async {
      await montar(tester, const NewSalePage(), vazio());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('venda com servidor fora assenta', (tester) async {
      await montar(tester, const NewSalePage(), falhando());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('operação duplicada', () {
    testWidgets('duas finalizações simultâneas enviam uma venda só',
        (tester) async {
      // No controller, e não na tela: na tela o segundo toque nunca chega ao
      // botão — a espera bloqueante o cobre —, e o teste passaria mesmo sem
      // proteção nenhuma. A garantia que importa é `finish()` recusar a
      // segunda chamada enquanto a primeira está em curso.
      final transport = RecordingTransport((request) {
        if (request.url.path.endsWith('/sales/')) {
          return jsonResponse(saleJson(), statusCode: 201);
        }
        return jsonResponse(const {'results': <Object?>[]});
      });
      final deps = buildTestDependencies(transport: transport);

      final controller = NewSaleController(
        catalog: deps.catalog,
        createSale: deps.createSale,
        scanner: deps.scanner,
      );
      addTearDown(controller.dispose);

      controller.addManual(
        category: const ProductCategory(id: 1, code: 'PECAS', name: 'Peças'),
        price: const Money.fromCents(12000),
      );

      // Sem esperar a primeira: é o dedo apressado no balcão.
      final primeira = controller.finish();
      final segunda = controller.finish();
      await Future.wait([primeira, segunda]);

      final vendas = transport.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
      );
      expect(vendas, hasLength(1));
    });
  });
}

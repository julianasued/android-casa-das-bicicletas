/// As telas cabem no M10, inclusive com a fonte do sistema ampliada (§21).
///
/// O M10 Pro é um aparelho de 5". Três estouros de layout já passaram por aqui
/// — o teclado da senha perdendo a última linha, o painel da venda passando
/// 102px, o menu cortando a última opção —, e todos só apareceram quando algum
/// teste renderizou a tela por acaso. Este arquivo faz isso de propósito.
///
/// A escala de fonte não é capricho: o operador de balcão costuma aumentar o
/// texto nas configurações do Android, e é aí que o layout estoura.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/sale/customer_picker_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/new_sale_page.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:casa_das_bicicletas/presentation/seller/seller_selection_page.dart';
import 'package:casa_das_bicicletas/presentation/terminal/terminal_login_page.dart';
import 'package:casa_das_bicicletas/presentation/welcome/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:casa_das_bicicletas/data/remote/mappers.dart';

import '../support/fakes.dart';

/// Tela do M10 Pro em pixels lógicos.
const Size _m10 = Size(360, 640);

void main() {
  RecordingTransport tudoQueAsTelasPedem() => RecordingTransport((request) {
        final caminho = request.url.path;
        if (caminho.contains('product-categories')) {
          return jsonResponse(const {
            'results': [
              {'id': 1, 'code': 'PECAS', 'name': 'Peças', 'is_active': true},
              {'id': 2, 'code': 'PNEUS', 'name': 'Pneus', 'is_active': true},
              {'id': 3, 'code': 'OLEOS', 'name': 'Óleos', 'is_active': true},
            ],
          });
        }
        if (caminho.contains('receivables')) {
          return jsonResponse(const {
            'results': [
              {
                'id': 501,
                'sale_id': 10482,
                'original_amount': '1500.00',
                'paid_amount': '0.00',
                'pending_amount': '1500.00',
                'status': 'VENCIDA',
                'created_at': '2026-08-05T14:32:00Z',
              },
            ],
          });
        }
        if (caminho.contains('customers')) {
          return jsonResponse(const {
            'results': [
              {
                'id': 77,
                'name': 'Maria Aparecida de Oliveira Santos',
                'document': '12345678909',
                'phone': '11999990000',
                'is_active': true,
              },
            ],
          });
        }
        if (caminho.contains('sellers')) {
          return jsonResponse(const {
            'results': [
              {'id': 12, 'name': 'João Carlos da Silva Pereira'},
              {'id': 15, 'name': 'Maria Costa'},
            ],
          });
        }
        return jsonResponse(const {'results': <Object?>[]});
      });

  /// Renderiza a tela no M10 e devolve o erro de layout, se houver.
  Future<Object?> renderizar(
    WidgetTester tester,
    Widget tela, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = _m10;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: tudoQueAsTelasPedem()),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: tela,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('rota')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  SaleFinished desfecho() {
    final json = saleJson();
    json['document_1'] = documentJson();
    return SaleFinished(
      result: saleWithDocumentFromJson(json),
      pendingOperationId: 'fila-local',
    );
  }

  final telas = <String, Widget Function()>{
    'inicial': () => const WelcomePage(),
    'senha do terminal': () => const TerminalLoginPage(),
    'seleção de vendedor': () => const SellerSelectionPage(
          sellers: [
            Seller(id: 12, name: 'João Carlos da Silva Pereira'),
            Seller(id: 15, name: 'Maria Costa'),
          ],
        ),
    'nova venda': () => const NewSalePage(),
    'busca de cliente': () => const CustomerPickerPage(),
  };

  group('cabem no M10 (360x640)', () {
    for (final entrada in telas.entries) {
      testWidgets('${entrada.key} não estoura', (tester) async {
        expect(await renderizar(tester, entrada.value()), isNull);
      });
    }

    testWidgets('venda finalizada não estoura', (tester) async {
      expect(await renderizar(tester, SaleFinishedPage(finished: desfecho())), isNull);
    });
  });

  group('cabem com a fonte ampliada em 30%', () {
    for (final entrada in telas.entries) {
      testWidgets('${entrada.key} não estoura', (tester) async {
        expect(
          await renderizar(tester, entrada.value(), textScale: 1.3),
          isNull,
        );
      });
    }

    testWidgets('venda finalizada não estoura', (tester) async {
      expect(
        await renderizar(
          tester,
          SaleFinishedPage(finished: desfecho()),
          textScale: 1.3,
        ),
        isNull,
      );
    });
  });
}

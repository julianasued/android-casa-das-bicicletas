/// O vendedor cancela a própria venda no M10, sem PIN (09/11/2026).
///
/// O botão CANCELAR VENDA ficou no lugar do CONFERIR PAGAMENTO. O que se
/// garante aqui: o motivo é obrigatório, a chamada vai para `cancel-own/` com
/// ele, a tela passa a dizer "Cancelada" e para de oferecer cancelar e
/// reimprimir — e a recusa do servidor (venda já paga) chega ao vendedor.
library;

import 'dart:convert';

import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  RecordingTransport servidorQueCancela() => RecordingTransport(
        (_) => jsonResponse({'id': 1, 'sale_id': 10482, 'reason': 'ok'}),
      );

  Future<void> montar(WidgetTester tester, RecordingTransport http) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final json = saleJson();
    json['document_1'] = documentJson();

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: http),
        child: MaterialApp(
          home: SaleFinishedPage(
            finished: SaleFinished(result: saleWithDocumentFromJson(json)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirCancelamento(WidgetTester tester) async {
    await tester.ensureVisible(find.text('CANCELAR VENDA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCELAR VENDA'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('confirmar-cancelamento')));
    await tester.tap(find.byKey(const Key('confirmar-cancelamento')));
    await tester.pumpAndSettle();
  }

  bool podeTocar(WidgetTester tester, Finder botao) =>
      tester.widget<ButtonStyleButton>(botao).onPressed != null;

  testWidgets('cancela com o motivo escolhido e a tela diz Cancelada',
      (tester) async {
    final http = servidorQueCancela();
    await montar(tester, http);

    await abrirCancelamento(tester);
    expect(find.text('CANCELAR A VENDA?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('motivo-Cliente desistiu')));
    await tester.pumpAndSettle();
    await confirmar(tester);

    final pedido = http.requests.single;
    expect(pedido.method, 'POST');
    expect(pedido.url.path, endsWith('/sales/10482/cancel-own/'));
    final corpo = pedido.body is String
        ? jsonDecode(pedido.body! as String)
        : pedido.body;
    expect((corpo as Map)['reason'], 'Cliente desistiu');

    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.text('VENDA CANCELADA'), findsOneWidget);
    expect(podeTocar(tester, find.byKey(const Key('cancelar-venda'))), isFalse);
  });

  testWidgets('sem motivo não confirma, e VOLTAR não cancela nada',
      (tester) async {
    final http = servidorQueCancela();
    await montar(tester, http);

    await abrirCancelamento(tester);
    expect(
      podeTocar(tester, find.byKey(const Key('confirmar-cancelamento'))),
      isFalse,
    );

    // "Outro motivo" exige escrever: duas letras ainda não bastam.
    await tester.tap(find.byKey(const Key('motivo-Outro motivo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('motivo-digitado')), 'ab');
    await tester.pumpAndSettle();
    expect(
      podeTocar(tester, find.byKey(const Key('confirmar-cancelamento'))),
      isFalse,
    );

    await tester.tap(find.text('VOLTAR'));
    await tester.pumpAndSettle();

    expect(http.requests, isEmpty);
    expect(find.text('CANCELAR VENDA'), findsOneWidget);
  });

  testWidgets('motivo escrito vai como foi escrito', (tester) async {
    final http = servidorQueCancela();
    await montar(tester, http);

    await abrirCancelamento(tester);
    await tester.tap(find.byKey(const Key('motivo-Outro motivo')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('motivo-digitado')),
      'Trocou por outro aro',
    );
    await tester.pumpAndSettle();
    await confirmar(tester);

    final corpo = http.requests.single.body;
    final mapa = corpo is String ? jsonDecode(corpo) : corpo;
    expect((mapa as Map)['reason'], 'Trocou por outro aro');
  });

  testWidgets('venda já paga: a recusa do servidor chega ao vendedor',
      (tester) async {
    final http = RecordingTransport(
      (_) => errorResponse(
        statusCode: 422,
        code: 'INVALID_STATE_TRANSITION',
        message: 'Esta venda já passou pelo caixa: o cancelamento agora é no '
            'computador, com o PIN do Dono ou do Gerente.',
      ),
    );
    await montar(tester, http);

    await abrirCancelamento(tester);
    await tester.tap(find.byKey(const Key('motivo-Venda errada')));
    await tester.pumpAndSettle();
    await confirmar(tester);

    expect(find.textContaining('já passou pelo caixa'), findsOneWidget);
    expect(find.text('Cancelada'), findsNothing);
    expect(podeTocar(tester, find.byKey(const Key('cancelar-venda'))), isTrue);
  });
}

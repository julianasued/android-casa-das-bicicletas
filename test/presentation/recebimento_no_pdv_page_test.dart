/// Tela de recebimento no PDV, quando a venda foi feita sem internet.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_queue.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:casa_das_bicicletas/presentation/sale/offline_payment_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _Fila implements SyncQueue {
  final List<PendingOperation> enfileiradas = [];

  @override
  Future<void> enqueue(PendingOperation operation) async =>
      enfileiradas.add(operation);

  @override
  Future<List<PendingOperation>> needingAttention() async => const [];

  @override
  Future<PendingOperation?> find(String operationId) async => null;

  @override
  Future<QueueSummary> summary() async =>
      QueueSummary(pending: enfileiradas.length, failed: 0, conflicting: 0);
}

void main() {
  late _Fila fila;
  late FakeDocumentPrinter impressora;

  SaleFinished vendaOffline({String forma = 'DINHEIRO', String desconto = '0.00'}) {
    final json = saleJson(id: 0)
      ..['payment_method'] = forma
      ..['created_offline'] = true
      ..['discount_amount'] = desconto
      ..['document_1'] = documentJson();
    return SaleFinished(
      result: saleWithDocumentFromJson(json),
      pendingOperationId: json['uuid']! as String,
      documentHeld: true,
    );
  }

  Future<void> montar(WidgetTester tester, SaleFinished finished) async {
    fila = _Fila();
    impressora = FakeDocumentPrinter();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(
          syncQueue: fila,
          printer: impressora,
          receiveAtTerminalWhenOffline: true,
        ),
        child: MaterialApp(
          home: OfflinePaymentPage(finished: finished),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dinheiro: mostra o troco e recebe', (tester) async {
    await montar(tester, vendaOffline());

    expect(find.text('RECEBER PAGAMENTO'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('valor-recebido')), '1600');
    await tester.pump();
    expect(find.textContaining('Troco: R\$'), findsOneWidget);
    expect(find.textContaining('100,00'), findsWidgets);

    await tester.tap(find.byKey(const Key('confirmar-recebimento')));
    await tester.pumpAndSettle();

    expect(fila.enfileiradas.single.type, OperationType.cashPayment);
    expect(impressora.printed, hasLength(1));
    expect(find.text('RECEBIDO NO PDV'), findsOneWidget);
  });

  testWidgets('dinheiro a menos que o total não deixa confirmar', (tester) async {
    await montar(tester, vendaOffline());

    await tester.enterText(find.byKey(const Key('valor-recebido')), '100');
    await tester.pump();

    expect(find.text('Valor menor que o devido em dinheiro.'), findsOneWidget);
    final botao = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('confirmar-recebimento')),
    );
    expect(botao.onPressed, isNull);
  });

  testWidgets('pagar no caixa imprime o encaminhamento e não recebe', (tester) async {
    await montar(tester, vendaOffline(forma: 'PIX'));

    await tester.tap(find.byKey(const Key('pagar-no-caixa')));
    await tester.pumpAndSettle();

    expect(fila.enfileiradas, isEmpty);
    expect(impressora.printed, hasLength(1));
    expect(find.text('rota: /venda/concluida'), findsOneWidget);
  });

  testWidgets('troca a forma: vendida em PIX, recebida em débito', (tester) async {
    await montar(tester, vendaOffline(forma: 'PIX'));

    await tester.tap(find.byKey(const Key('forma-primeira-DEBITO')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmar-recebimento')));
    await tester.pumpAndSettle();

    expect(fila.enfileiradas.single.payload['payments'], [
      {'payment_method': 'DEBITO', 'amount': '1500.00'},
    ]);
  });

  testWidgets('divide entre dinheiro e PIX, com troco só sobre o dinheiro',
      (tester) async {
    await montar(tester, vendaOffline());

    await tester.tap(find.byKey(const Key('dividir-pagamento')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('valor-da-primeira')), '1000');
    await tester.tap(find.byKey(const Key('forma-segunda-PIX')));
    await tester.pump();
    expect(find.text('Em PIX: R\$ 500,00'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('valor-recebido')), '1100');
    await tester.pump();
    expect(find.text('Troco: R\$ 100,00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmar-recebimento')));
    await tester.pumpAndSettle();

    expect(fila.enfileiradas.single.payload['payments'], [
      {'payment_method': 'DINHEIRO', 'amount': '1000.00'},
      {'payment_method': 'PIX', 'amount': '500.00'},
    ]);
  });

  testWidgets('dividir sem segunda forma não deixa confirmar', (tester) async {
    await montar(tester, vendaOffline(forma: 'PIX'));

    await tester.tap(find.byKey(const Key('dividir-pagamento')));
    await tester.pump();

    expect(find.text('Escolha a segunda forma.'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('confirmar-recebimento')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('venda com desconto não oferece crédito', (tester) async {
    await montar(tester, vendaOffline(forma: 'PIX', desconto: '10.00'));

    final credito = tester.widget<ChoiceChip>(
      find.byKey(const Key('forma-primeira-CREDITO')),
    );
    expect(credito.onSelected, isNull);
    expect(find.text('Venda com desconto não pode ser no crédito.'), findsOneWidget);
  });

  test('o comprovante emitido é o documento 2', () {
    expect(DocumentType.doc2.label, 'Retirada da compra');
  });
}

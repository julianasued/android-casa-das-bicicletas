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

  SaleFinished vendaOffline({String forma = 'DINHEIRO'}) {
    final json = saleJson(id: 0)
      ..['payment_method'] = forma
      ..['created_offline'] = true
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

    expect(find.text('Valor menor que o total.'), findsOneWidget);
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

  test('o comprovante emitido é o documento 2', () {
    expect(DocumentType.doc2.label, 'Retirada da compra');
  });
}

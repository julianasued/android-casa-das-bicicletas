/// Sem internet, o vendedor recebe no próprio PDV.
///
/// O caixa não enxerga a venda que só existe na fila deste aparelho, então a
/// confirmação nasce aqui e sobe junto: a venda primeiro, o pagamento depois,
/// na mesma fila.
library;

import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/entities/sale.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_identity.dart';
import 'package:casa_das_bicicletas/domain/repositories/sale_repository.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_queue.dart';
import 'package:casa_das_bicicletas/domain/rules/offline_sale_context.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/domain/usecases/receive_offline_payment.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _SemRede implements SaleRepository {
  @override
  Future<Result<SaleWithDocument>> create(SaleDraft draft) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<Sale>> findByBarcode(String barcode) => throw UnimplementedError();

  @override
  Future<Result<Sale>> findById(int saleId) => throw UnimplementedError();

  @override
  Future<Result<PrintedDocument>> reprintDocument(int saleId, DocumentType type) =>
      throw UnimplementedError();

  @override
  Map<String, Object?> payloadFor(SaleDraft draft) => {'uuid': draft.uuid};
}

void main() {
  late _Fila fila;
  late FakeDocumentPrinter impressora;

  setUp(() {
    fila = _Fila();
    impressora = FakeDocumentPrinter();
  });

  CreateSale vender() => CreateSale(
        sales: _SemRede(),
        printer: impressora,
        queue: fila,
        holdOfflineDocument: true,
        offlineContext: () async => OfflineSaleContext(
          identity: TerminalIdentity(
            storeCode: 'L1',
            storeName: 'Casa das Bicicletas',
            learnedAt: DateTime.utc(2026, 11, 1),
          ),
          seller: const Seller(id: 12, name: 'João Silva'),
          storeCode: 'L1',
          storeId: 1,
          payload: (draft) => {'uuid': draft.uuid},
        ),
      );

  SaleDraft rascunho(PaymentMethod forma) => SaleDraft()
    ..add(
      Product(
        id: 10,
        sku: 'PNEU',
        name: 'Pneu Aro 15',
        categoryCode: 'PNEUS',
        categoryName: 'Pneus',
        price: const Money.fromCents(25000),
      ),
    )
    ..paymentMethod = forma
    ..customer = forma.requiresCustomer
        ? const Customer(id: 5, name: 'Carlos Lima')
        : null;

  ReceiveOfflinePayment receber() => ReceiveOfflinePayment(
        queue: fila,
        printer: impressora,
        clock: () => DateTime(2026, 11, 5, 15),
        newId: () => 'op-pagamento',
      );

  Future<SaleFinished> venderSemRede(PaymentMethod forma) async =>
      ((await vender()(rascunho(forma))) as Ok<SaleFinished>).value;

  test('sem rede, a venda vai para a fila e o papel espera a escolha', () async {
    final venda = await venderSemRede(PaymentMethod.dinheiro);

    expect(venda.documentHeld, isTrue);
    expect(fila.enfileiradas, hasLength(1));
    expect(impressora.printed, isEmpty);
  });

  test('receber enfileira o pagamento depois da venda e imprime o comprovante',
      () async {
    final venda = await venderSemRede(PaymentMethod.dinheiro);

    final r = await receber()(
      sale: venda.result.sale,
      document1: venda.result.document!,
      receiverName: 'João Silva',
    );
    final recebido = (r as Ok<OfflinePaymentReceived>).value;

    expect(fila.enfileiradas.map((o) => o.type),
        [OperationType.saleCreate, OperationType.cashPayment]);
    final pagamento = fila.enfileiradas.last;
    expect(pagamento.operationId, 'op-pagamento');
    expect(pagamento.payload['sale_uuid'], venda.result.sale.uuid);
    expect(pagamento.payload['payments'], [
      {'payment_method': 'DINHEIRO', 'amount': '250.00'},
    ]);
    expect(
      pagamento.occurredAt.isAfter(fila.enfileiradas.first.occurredAt),
      isTrue,
    );

    expect(recebido.sale.status, SaleStatus.paga);
    expect(recebido.document.type, DocumentType.doc2);
    expect(recebido.document.cashierName, 'João Silva');
    expect(impressora.printed, hasLength(1));
  });

  test('notinha confirma a entrega sem recebimento', () async {
    final venda = await venderSemRede(PaymentMethod.notinha);

    final r = await receber()(
      sale: venda.result.sale,
      document1: venda.result.document!,
      receiverName: 'João Silva',
    );

    expect(fila.enfileiradas.last.payload['payments'], isEmpty);
    expect((r as Ok<OfflinePaymentReceived>).value.sale.status,
        SaleStatus.pendenteNotinha);
  });

  test('o pagamento nunca fica antes da venda, nem com o relógio atrasado',
      () async {
    final venda = await venderSemRede(PaymentMethod.pix);
    final atrasado = ReceiveOfflinePayment(
      queue: fila,
      printer: impressora,
      clock: () => DateTime(2000),
    );

    await atrasado(
      sale: venda.result.sale,
      document1: venda.result.document!,
      receiverName: 'João Silva',
    );

    expect(
      fila.enfileiradas.last.occurredAt
          .isAfter(fila.enfileiradas.first.occurredAt),
      isTrue,
    );
  });

  test('venda feita com internet não é recebida no PDV', () async {
    final venda = await venderSemRede(PaymentMethod.pix);
    final online = Sale(
      id: 99,
      uuid: venda.result.sale.uuid,
      storeId: 1,
      sellerId: 12,
      sellerName: 'João Silva',
      status: SaleStatus.aguardandoCaixa,
      paymentMethod: PaymentMethod.pix,
      barcode: 'X',
      grossAmount: const Money.fromCents(25000),
      discountAmount: const Money.fromCents(0),
      totalAmount: const Money.fromCents(25000),
      items: const [],
      occurredAt: DateTime(2026, 11, 5),
    );

    final r = await receber()(
      sale: online,
      document1: venda.result.document!,
      receiverName: 'João Silva',
    );

    expect(r, isA<Err<OfflinePaymentReceived>>());
    expect(fila.enfileiradas, hasLength(1));
  });
}

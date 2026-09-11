/// A venda que acontece sem rede (§13.9, RF35).
///
/// O que se cobra aqui é o desfecho no balcão: o cliente sai com papel na mão, a
/// venda fica registrada no aparelho, e nada disso se confunde com uma venda
/// recusada pelo servidor — que é coisa que o vendedor pode corrigir.
library;

import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/entities/sale.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_identity.dart';
import 'package:casa_das_bicicletas/domain/rules/offline_document.dart';
import 'package:casa_das_bicicletas/domain/rules/offline_sale_context.dart';
import 'package:casa_das_bicicletas/domain/repositories/sale_repository.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_queue.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/ports/document_printer.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Product _pneu() => Product(
      id: 10,
      sku: 'PNEU-A15-001',
      name: 'Pneu Aro 15',
      categoryCode: 'PNEUS',
      categoryName: 'Pneus',
      price: const Money.fromCents(25000),
    );

TerminalIdentity _identidade({String storeName = 'Casa das Bicicletas Centro'}) =>
    TerminalIdentity(
      storeCode: 'L1',
      storeName: storeName,
      storeDocument: '12345678000190',
      storeAddress: 'Rua das Flores, 100',
      terminalName: 'Caixa 1 - Loja 1',
      learnedAt: DateTime.utc(2026, 9, 10),
    );

OfflineSaleContext _contexto({TerminalIdentity? identity}) => OfflineSaleContext(
      identity: identity ?? _identidade(),
      seller: const Seller(id: 12, name: 'João Silva'),
      storeCode: 'L1',
      storeId: 1,
      payload: (draft) => {'uuid': draft.uuid, 'items': draft.lineCount},
    );

/// Fila em memória: o que se testa aqui é a decisão do caso de uso, não o SQL.
class _FilaEspia implements SyncQueue {
  final List<PendingOperation> enfileiradas = [];

  @override
  Future<void> enqueue(PendingOperation operation) async =>
      enfileiradas.add(operation);

  @override
  Future<QueueSummary> summary() async => QueueSummary(
        pending: enfileiradas.length,
        failed: 0,
        conflicting: 0,
      );
}

class _VendasStub implements SaleRepository {
  _VendasStub(this.response);

  final Result<SaleWithDocument> response;

  @override
  Future<Result<SaleWithDocument>> create(SaleDraft draft) async => response;

  @override
  Future<Result<Sale>> findByBarcode(String barcode) =>
      throw UnimplementedError();

  @override
  Future<Result<Sale>> findById(int saleId) => throw UnimplementedError();

  @override
  Future<Result<PrintedDocument>> reprintDocument(
    int saleId,
    DocumentType type,
  ) =>
      throw UnimplementedError();
  @override
  Map<String, Object?> payloadFor(SaleDraft draft) => {'uuid': draft.uuid};

}

void main() {
  late _FilaEspia fila;
  late FakeDocumentPrinter impressora;

  SaleDraft draft() => SaleDraft()
    ..add(_pneu())
    ..paymentMethod = PaymentMethod.pix;

  CreateSale semRede({OfflineSaleContext? contexto}) => CreateSale(
        sales: _VendasStub(const Err(NetworkFailure())),
        printer: impressora,
        queue: fila,
        offlineContext: () async => contexto ?? _contexto(),
      );

  setUp(() {
    fila = _FilaEspia();
    impressora = FakeDocumentPrinter();
  });

  group('sem rede, a venda acontece', () {
    test('entra na fila e o papel sai', () async {
      final resultado = await semRede()(draft());

      expect(resultado, isA<Ok<SaleFinished>>());
      final desfecho = (resultado as Ok<SaleFinished>).value;

      expect(desfecho.awaitsSync, isTrue);
      expect(desfecho.printed, isTrue);
      expect(fila.enfileiradas, hasLength(1));
      expect(impressora.printed, hasLength(1));
    });

    test('a operação na fila carrega o uuid da venda (RF36)', () async {
      final venda = draft();
      await semRede()(venda);

      final operacao = fila.enfileiradas.single;
      expect(operacao.operationId, venda.uuid);
      expect(operacao.type, OperationType.saleCreate);
      expect(operacao.status, SyncStatus.pendente);
      expect(operacao.payload['uuid'], venda.uuid);
    });

    test('a fila recebe antes de o papel sair', () async {
      // Um documento impresso de uma venda que não ficou registrada em lugar
      // nenhum é o pior desfecho possível.
      final semPapel = FakeDocumentPrinter(
        currentStatus: const PrinterStatus(available: true, outOfPaper: true),
      );
      final usecase = CreateSale(
        sales: _VendasStub(const Err(NetworkFailure())),
        printer: semPapel,
        queue: fila,
        offlineContext: () async => _contexto(),
      );

      final resultado = await usecase(draft());
      final desfecho = (resultado as Ok<SaleFinished>).value;

      expect(fila.enfileiradas, hasLength(1));
      expect(desfecho.printed, isFalse);
      // A venda existe mesmo sem papel: a saída é reimprimir, não cancelar.
      expect(desfecho.awaitsSync, isTrue);
      expect(semPapel.printed, isEmpty);
    });
  });

  group('o documento provisório', () {
    test('diz que o número sai depois, em vez de inventar um', () async {
      final resultado = await semRede()(draft());
      final documento =
          (resultado as Ok<SaleFinished>).value.result.document!;

      expect(documento.reference, pendingReferenceLabel);
      expect(documento.saleId, 0);
      expect(documento.notice, contains('sem conexao'));
    });

    test('o código de barras é o de valer, calculado do uuid', () async {
      // É o que o caixa lê para achar a venda (RF09), e a regra é a mesma do
      // backend — este campo não é provisório.
      final venda = draft();
      final resultado = await semRede()(venda);
      final documento =
          (resultado as Ok<SaleFinished>).value.result.document!;

      expect(documento.saleBarcode, venda.barcodeFor('L1'));
      expect(documento.saleBarcode, startsWith('SALE-L1-'));
    });

    test('traz loja, vendedor, terminal e itens', () async {
      final resultado = await semRede()(draft());
      final documento =
          (resultado as Ok<SaleFinished>).value.result.document!;

      expect(documento.storeName, 'Casa das Bicicletas Centro');
      expect(documento.storeDocument, '12345678000190');
      expect(documento.sellerName, 'João Silva');
      expect(documento.terminalName, 'Caixa 1 - Loja 1');
      expect(documento.items, hasLength(1));
      expect(documento.items.single.productName, 'Pneu Aro 15');
      expect(documento.totalAmount, const Money.fromCents(25000));
    });

    test('o desconto rateado sai do total apurado, sem conta nova', () async {
      // Recalcular aqui abriria espaço para o papel divergir em um centavo do
      // que o servidor vai gravar.
      final venda = draft()
        ..add(_pneu())
        ..discountPercentHundredths = 500;

      final resultado = await semRede()(venda);
      final documento =
          (resultado as Ok<SaleFinished>).value.result.document!;

      final totals = venda.totals;
      expect(documento.discountAmount, totals.discount);
      expect(
        documento.items.single.lineTotal,
        totals.lineTotals.single,
      );
    });
  });

  group('a venda local', () {
    test('nasce aguardando caixa, e não em limbo', () async {
      // `PENDENTE_SINCRONIZACAO` é estado da operação na fila, não da venda: ela
      // está feita, só falta subir.
      final resultado = await semRede()(draft());
      final venda = (resultado as Ok<SaleFinished>).value.result.sale;

      expect(venda.status, SaleStatus.aguardandoCaixa);
      expect(venda.createdOffline, isTrue);
      expect(venda.id, 0);
    });
  });

  group('o que não vira fila', () {
    test('recusa do servidor chega ao vendedor, que pode corrigir', () async {
      // Enfileirar um 422 faria a venda "dar certo" no balcão para ser recusada
      // de novo a cada sincronização.
      final usecase = CreateSale(
        sales: _VendasStub(
          const Err(
            ApiFailure(
              statusCode: 422,
              code: 'VALIDATION_ERROR',
              message: 'Desconto acima do teto',
            ),
          ),
        ),
        printer: impressora,
        queue: fila,
        offlineContext: () async => _contexto(),
      );

      final resultado = await usecase(draft());

      expect(resultado, isA<Err<SaleFinished>>());
      expect(fila.enfileiradas, isEmpty);
      expect(impressora.printed, isEmpty);
    });

    test('sem o mínimo para o cupom, a falha de rede segue seu caminho',
        () async {
      // Melhor o vendedor saber que não deu do que receber um papel que não
      // identifica a loja.
      final resultado = await semRede(
        contexto: _contexto(identity: _identidade(storeName: '')),
      )(draft());

      expect(resultado, isA<Err<SaleFinished>>());
      expect((resultado as Err<SaleFinished>).failure, isA<NetworkFailure>());
      expect(fila.enfileiradas, isEmpty);
      expect(impressora.printed, isEmpty);
    });

    test('sem fila configurada, o caso de uso age como antes', () async {
      final usecase = CreateSale(
        sales: _VendasStub(const Err(NetworkFailure())),
        printer: impressora,
      );

      final resultado = await usecase(draft());
      expect(resultado, isA<Err<SaleFinished>>());
      expect(impressora.printed, isEmpty);
    });

    test('carrinho com problema não chega nem a tentar a rede', () async {
      // Notinha exige cliente (RF14): é erro de regra, não de conexão.
      final venda = SaleDraft()
        ..add(_pneu())
        ..paymentMethod = PaymentMethod.notinha;

      final resultado = await semRede()(venda);

      expect(resultado, isA<Err<SaleFinished>>());
      expect(
        (resultado as Err<SaleFinished>).failure,
        isA<BusinessRuleFailure>(),
      );
      expect(fila.enfileiradas, isEmpty);
    });
  });

  group('com rede, nada muda', () {
    test('vai ao servidor e não usa a fila', () async {
      final usecase = CreateSale(
        sales: _VendasStub(
          Ok(
            SaleWithDocument(
              sale: saleFromJson(saleJson()),
              document: printedDocumentFromJson(documentJson()),
            ),
          ),
        ),
        printer: impressora,
        queue: fila,
        offlineContext: () async => _contexto(),
      );

      final resultado = await usecase(draft());
      final desfecho = (resultado as Ok<SaleFinished>).value;

      expect(desfecho.awaitsSync, isFalse);
      expect(fila.enfileiradas, isEmpty);
      expect(desfecho.result.document!.reference, isNot(pendingReferenceLabel));
    });
  });
}

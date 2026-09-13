import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/entities/sale.dart';
import 'package:casa_das_bicicletas/domain/ports/document_printer.dart';
import 'package:casa_das_bicicletas/domain/repositories/sale_repository.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/platform/printer/printer_channel.dart';
import 'package:flutter_test/flutter_test.dart';

class _SaleRepositoryStub implements SaleRepository {
  _SaleRepositoryStub(this.response);

  final Result<SaleWithDocument> response;
  int calls = 0;

  @override
  Future<Result<SaleWithDocument>> create(SaleDraft draft) async {
    calls++;
    return response;
  }

  @override
  Future<Result<Sale>> findByBarcode(String barcode) =>
      throw UnimplementedError();

  @override
  Future<Result<Sale>> findById(int saleId) => throw UnimplementedError();

  @override
  Future<Result<PrintedDocument>> reprintDocument(int saleId, DocumentType type) =>
      throw UnimplementedError();
  @override
  Map<String, Object?> payloadFor(SaleDraft draft) => {'uuid': draft.uuid};

}

Product _pneu() => Product(
      id: 10,
      sku: 'PNEU-A15-001',
      name: 'Pneu Aro 15',
      categoryCode: 'PNEUS',
      categoryName: 'Pneus',
      price: const Money.fromCents(25000),
    );

SaleWithDocument _registered() => SaleWithDocument(
      sale: Sale(
        id: 10482,
        uuid: '7f3a9c2b-1111-4222-8333-444455556666',
        storeId: 1,
        sellerId: 12,
        sellerName: 'João Silva',
        status: SaleStatus.aguardandoCaixa,
        paymentMethod: PaymentMethod.pix,
        barcode: 'SALE-L1-7F3A9C2B',
        grossAmount: const Money.fromCents(150000),
        discountAmount: const Money.zero(),
        totalAmount: const Money.fromCents(150000),
        items: const [],
        occurredAt: DateTime(2026, 8, 5, 14, 32),
      ),
      document: _document(),
    );

PrintedDocument _document() => PrintedDocument(
      type: DocumentType.doc1,
      reference: 'DOC1-L1-7F3A9C2B',
      sequence: 1,
      isReprint: false,
      printedAt: DateTime(2026, 8, 5, 14, 32),
      printedByName: 'João Silva',
      storeCode: 'L1',
      storeName: 'Casa das Bicicletas Centro',
      storeDocument: '12345678000190',
      storeAddress: 'Rua das Flores, 100',
      saleId: 10482,
      saleBarcode: 'SALE-L1-7F3A9C2B',
      saleOccurredAt: DateTime(2026, 8, 5, 14, 32),
      paymentMethodLabel: 'PIX',
      sellerName: 'João Silva',
      terminalName: 'Caixa 1',
      items: const [],
      grossAmount: const Money.fromCents(150000),
      discountAmount: const Money.zero(),
      totalAmount: const Money.fromCents(150000),
      notice: 'Não é comprovante de pagamento.',
    );

void main() {
  test('registra a venda e imprime o documento 1', () async {
    final repository = _SaleRepositoryStub(Ok(_registered()));
    final printer = FakeDocumentPrinter();
    final usecase = CreateSale(sales: repository, printer: printer);

    final result = await usecase(SaleDraft()..add(_pneu()));
    final finished = (result as Ok<SaleFinished>).value;

    expect(finished.printed, isTrue);
    expect(finished.result.sale.id, 10482);
    expect(printer.printed, hasLength(1));
  });

  test('falha de impressão não desfaz a venda', () async {
    // O caso real: acabou a bobina. A venda está registrada, o cliente está no
    // balcão, e o que resolve é reimprimir — não cancelar o que foi vendido.
    final repository = _SaleRepositoryStub(Ok(_registered()));
    final printer = FakeDocumentPrinter(
      currentStatus: const PrinterStatus(available: true, outOfPaper: true),
    );
    final usecase = CreateSale(sales: repository, printer: printer);

    final result = await usecase(SaleDraft()..add(_pneu()));
    final finished = (result as Ok<SaleFinished>).value;

    expect(finished.result.sale.id, 10482, reason: 'a venda existe');
    expect(finished.printed, isFalse);
    expect(finished.printFailure, isA<OutOfPaperFailure>());
  });

  test('venda inválida não chega ao servidor', () async {
    final repository = _SaleRepositoryStub(Ok(_registered()));
    final usecase = CreateSale(sales: repository, printer: FakeDocumentPrinter());

    // Carrinho vazio: o domínio recusa antes de qualquer requisição.
    final result = await usecase(SaleDraft());

    expect(result.failureOrNull, isA<BusinessRuleFailure>());
    expect(repository.calls, 0);
  });

  test('falha do servidor não vira documento impresso', () async {
    final repository = _SaleRepositoryStub(
      const Err(NetworkFailure()),
    );
    final printer = FakeDocumentPrinter();
    final usecase = CreateSale(sales: repository, printer: printer);

    final result = await usecase(SaleDraft()..add(_pneu()));

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(printer.printed, isEmpty);
  });
}

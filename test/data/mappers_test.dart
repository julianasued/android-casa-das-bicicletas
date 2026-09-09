import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/sale.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('venda', () {
    test('lê a resposta do POST /sales/ com o documento junto', () {
      final result = saleWithDocumentFromJson(saleJson());

      expect(result.sale.id, 10482);
      expect(result.sale.barcode, 'SALE-L1-7F3A9C2B');
      expect(result.sale.status, SaleStatus.aguardandoCaixa);
      expect(result.sale.paymentMethod, PaymentMethod.pix);
      expect(result.sale.totalAmount.toApiString(), '1500.00');
      expect(result.sale.items, hasLength(2));
      expect(result.document, isNotNull);
      expect(result.document!.type, DocumentType.doc1);
    });

    test('venda sem documento não vira erro de mapeamento', () {
      final result = saleWithDocumentFromJson(saleJson(withDocument: false));

      expect(result.sale.id, 10482);
      expect(result.document, isNull);
    });

    test('estado desconhecido não derruba a tela', () {
      final sale = saleFromJson(
        saleJson(status: 'ESTADO_NOVO_DO_SERVIDOR', withDocument: false),
      );
      expect(sale.status, SaleStatus.desconhecido);
    });

    test('mapeia o item com os campos que o terminal recebe', () {
      // §5 da API: comissão não vem no JSON deste perfil, e a entidade `SaleItem`
      // não tem onde guardá-la — o que sobra é o que se confere aqui.
      final item = saleFromJson(saleJson(withDocument: false)).items.first;

      expect(item.productName, 'Pneu Aro 15');
      expect(item.categoryCode, 'PNEUS');
      expect(item.quantity.toApiString(), '2.000');
      expect(item.lineTotal.toApiString(), '500.00');
    });
  });

  group('documento', () {
    test('descobre o tipo pela referência', () {
      expect(
        printedDocumentFromJson(documentJson()).type,
        DocumentType.doc1,
      );
      expect(
        printedDocumentFromJson(documentJson(reference: 'DOC2-L1-7F3A9C2B')).type,
        DocumentType.doc2,
      );
    });

    test('reconhece a via de reimpressão', () {
      final document = printedDocumentFromJson(
        documentJson(reference: 'DOC1-L1-7F3A9C2B-R2', sequence: 2),
      );

      expect(document.sequence, 2);
      expect(document.isReprint, isTrue);
    });

    test('traduz a forma de pagamento para o rótulo impresso', () {
      expect(printedDocumentFromJson(documentJson()).paymentMethodLabel, 'PIX');
    });
  });

  group('leitura do canal do leitor', () {
    test('monta a leitura com origem e horário', () {
      final read = barcodeReadFromChannel(const {
        'code': 'SALE-L1-7F3A9C2B',
        'symbology': 'CODE128',
        'read_at': '2026-08-05T14:40:00.000Z',
        'source': 'scanner',
      });

      expect(read.code, 'SALE-L1-7F3A9C2B');
      expect(read.symbology, 'CODE128');
      expect(read.looksLikeSaleBarcode, isTrue);
    });

    test('código de produto não é confundido com código de venda', () {
      final read = barcodeReadFromChannel(const {'code': '7891234567890'});
      expect(read.looksLikeSaleBarcode, isFalse);
    });
  });

  test('campo obrigatório ausente falha no mapeamento, não no papel', () {
    // Melhor errar aqui do que imprimir um documento com total zerado.
    expect(
      () => saleFromJson(const {'id': 1, 'store_id': 1}),
      throwsFormatException,
    );
  });
}

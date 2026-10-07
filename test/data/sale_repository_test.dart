import 'dart:convert';

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/repositories/sale_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
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

void main() {
  late RecordingTransport transport;
  late SaleRepositoryImpl repository;

  Future<void> prepare(RecordingTransport http) async {
    transport = http;
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    repository = SaleRepositoryImpl(deps.apiClient);
  }

  Map<String, Object?> sentBody() =>
      jsonDecode(jsonEncode(transport.lastRequest.body)) as Map<String, Object?>;

  group('POST /sales/', () {
    test('monta o corpo no formato do §3.4.1', () async {
      await prepare(RecordingTransport((_) => jsonResponse(saleJson(), statusCode: 201)));

      final draft = SaleDraft()
        ..add(_pneu())
        ..add(_pneu())
        ..paymentMethod = PaymentMethod.pix
        ..discountPercentHundredths = 250;

      await repository.create(draft);

      final body = sentBody();
      expect(body['uuid'], draft.uuid);
      expect(body['payment_method'], 'PIX');
      expect(body['discount_percent'], '2.50');
      expect(body['created_offline'], isFalse);

      final items = body['items']! as List<Object?>;
      expect(items, hasLength(1));

      final item = items.first! as Map<String, Object?>;
      expect(item['product_id'], 10);
      expect(item['quantity'], '2.000');
      expect(item['unit_price'], '250.00');
    });

    test('o uuid da venda é a chave de idempotência (§1.5)', () async {
      await prepare(RecordingTransport((_) => jsonResponse(saleJson(), statusCode: 201)));

      final draft = SaleDraft()..add(_pneu());
      await repository.create(draft);

      expect(
        transport.lastRequest.headers['X-Idempotency-Key'],
        draft.uuid,
        reason: 'reenviar a mesma venda precisa repetir a mesma chave',
      );
    });

    test('reenvio da mesma venda usa a mesma chave', () async {
      await prepare(RecordingTransport((_) => jsonResponse(saleJson(), statusCode: 201)));

      final draft = SaleDraft()..add(_pneu());
      await repository.create(draft);
      final primeira = transport.lastRequest.headers['X-Idempotency-Key'];

      await repository.create(draft);
      expect(transport.lastRequest.headers['X-Idempotency-Key'], primeira);
    });

    test('cliente entra no corpo apenas quando existe', () async {
      await prepare(RecordingTransport((_) => jsonResponse(saleJson(), statusCode: 201)));

      final draft = SaleDraft()..add(_pneu());
      await repository.create(draft);

      expect(sentBody().containsKey('customer_id'), isFalse);
    });

    test('devolve venda e documento prontos para imprimir', () async {
      await prepare(RecordingTransport((_) => jsonResponse(saleJson(), statusCode: 201)));

      final result = await repository.create(SaleDraft()..add(_pneu()));
      final value = (result as Ok<SaleWithDocument>).value;

      expect(value.sale.barcode, 'SALE-L1-7F3A9C2B');
      expect(value.document!.reference, 'DOC1-L1-7F3A9C2B');
    });
  });

  test('by-barcode monta a rota da RF09', () async {
    await prepare(
      RecordingTransport((_) => jsonResponse(saleJson(withDocument: false))),
    );

    await repository.findByBarcode('SALE-L1-7F3A9C2B');

    expect(
      transport.lastRequest.url.path,
      contains('sales/by-barcode/SALE-L1-7F3A9C2B/'),
    );
  });

  test('reimpressão chama a rota do documento pedido, sem idempotência', () async {
    await prepare(
      RecordingTransport((_) => jsonResponse(documentJson(sequence: 2), statusCode: 201)),
    );

    await repository.reprintDocument(10482, DocumentType.doc2);

    expect(
      transport.lastRequest.url.path,
      contains('sales/10482/document-2/print/'),
    );
    expect(
      transport.lastRequest.headers.containsKey('X-Idempotency-Key'),
      isFalse,
    );
  });
}

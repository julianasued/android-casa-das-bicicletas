import 'package:casa_das_bicicletas/core/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gera UUID v4 no formato canônico', () {
    final uuid = generateUuidV4();

    expect(uuid.length, 36);
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(uuid),
      isTrue,
      reason: 'versão 4 e variante RFC 4122',
    );
  });

  test('não repete identificador entre vendas', () {
    final gerados = {for (var i = 0; i < 500; i++) generateUuidV4()};
    expect(gerados.length, 500);
  });

  test('código de barras segue a forma que o backend gera', () {
    // `identifiers.sale_barcode`: SALE-<loja>-<8 primeiros hex do uuid>.
    final barcode = saleBarcodeFor(
      storeCode: 'L1',
      saleUuid: '7f3a9c2b-1111-4222-8333-444455556666',
    );
    expect(barcode, 'SALE-L1-7F3A9C2B');
  });
}

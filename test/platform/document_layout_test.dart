import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/platform/printer/document_layout.dart';
import 'package:casa_das_bicicletas/platform/printer/print_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const layout = DocumentLayout();

  group('documento 1 (RF08)', () {
    late List<PrintCommand> commands;
    late String papel;

    setUp(() {
      final document = printedDocumentFromJson(documentJson());
      commands = layout.build(document);
      papel = renderCommandsAsText(commands);
    });

    test('traz tudo o que o §7 da integração exige', () {
      expect(papel, contains('CASA DAS BICICLETAS CENTRO'));
      expect(papel, contains('ENCAMINHAMENTO AO CAIXA'));
      expect(papel, contains('#10482'));
      expect(papel, contains('João Silva'));
      expect(papel, contains('Pneu Aro 15'));
      expect(papel, contains('PIX'));
      expect(papel, contains('1.500,00'));
      expect(papel, contains('SALE-L1-7F3A9C2B'));
    });

    test('imprime o código de barras da venda (RF09)', () {
      final barcodes = commands.whereType<PrintBarcode>().toList();

      expect(barcodes, hasLength(1));
      expect(barcodes.single.data, 'SALE-L1-7F3A9C2B');
    });

    test('avisa que não é comprovante de pagamento', () {
      expect(papel.toLowerCase(), contains('não é comprovante'));
    });

    test('nenhuma linha ultrapassa a largura da bobina de 2"', () {
      for (final command in commands.whereType<PrintText>()) {
        expect(
          command.value.length,
          lessThanOrEqualTo(paperColumns),
          reason: 'linha estourada sai cortada no papel: "${command.value}"',
        );
      }
    });

    test('termina avançando o papel para o operador destacar', () {
      expect(commands.last, isA<PrintCut>());
    });
  });

  group('reimpressão', () {
    test('a via de reimpressão sai marcada no papel (§3.4.3)', () {
      final document = printedDocumentFromJson(
        documentJson(reference: 'DOC1-L1-7F3A9C2B-R2', sequence: 2),
      );
      final papel = renderCommandsAsText(layout.build(document));

      expect(papel, contains('REIMPRESSAO'));
      expect(papel, contains('2a VIA'));
    });
  });

  group('documento 2 (RF12)', () {
    test('acrescenta a confirmação do caixa', () {
      final json = Map<String, Object?>.from(
        documentJson(reference: 'DOC2-L1-7F3A9C2B'),
      )
        ..['confirmed_at'] = '2026-08-05T14:41:00Z'
        ..['cashier_name'] = 'Maria Costa'
        ..['payments'] = [
          {
            'payment_method': 'PIX',
            'amount': '1500.00',
            'occurred_at': '2026-08-05T14:41:00Z',
          },
        ];

      final papel = renderCommandsAsText(layout.build(printedDocumentFromJson(json)));

      expect(papel, contains('DOCUMENTO DE RETIRADA'));
      expect(papel, contains('PAGAMENTO CONFIRMADO'));
      expect(papel, contains('Maria Costa'));
    });
  });

  group('desconto', () {
    test('subtotal e desconto aparecem apenas quando há desconto', () {
      final semDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(documentJson())),
      );
      expect(semDesconto, isNot(contains('Subtotal')));

      final json = Map<String, Object?>.from(documentJson())
        ..['discount_amount'] = '75.00'
        ..['total_amount'] = '1425.00';

      final comDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );
      expect(comDesconto, contains('Subtotal'));
      expect(comDesconto, contains('75,00'));
    });
  });

  group('quebra de linha', () {
    test('nome longo de produto é quebrado, não cortado', () {
      final json = Map<String, Object?>.from(documentJson());
      final items = List<Map<String, Object?>>.from(
        (json['items']! as List<Object?>).cast<Map<String, Object?>>(),
      );
      items[0] = Map<String, Object?>.from(items[0])
        ..['product_name'] =
            'Pneu aro 29 para bicicleta de montanha com camara reforcada';
      json['items'] = items;

      final commands = layout.build(printedDocumentFromJson(json));
      final papel = renderCommandsAsText(commands);

      expect(papel, contains('Pneu aro 29 para bicicleta de'));
      expect(papel, contains('reforcada'));
      for (final command in commands.whereType<PrintText>()) {
        expect(command.value.length, lessThanOrEqualTo(paperColumns));
      }
    });
  });

  test('página de teste é imprimível sem venda nenhuma', () {
    final papel = renderCommandsAsText(
      layout.buildTestPage(terminalName: 'Caixa 1 - Loja 1'),
    );

    expect(papel, contains('TESTE DE IMPRESSAO'));
    expect(papel, contains('Caixa 1 - Loja 1'));
  });
}

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
    test('o sub-total sai sempre; o desconto, só quando existe', () {
      // O modelo da nota trata o sub-total como linha fixa: uma nota que
      // mostra só o total esconde a conta de quem confere no caixa.
      final semDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(documentJson())),
      );
      expect(semDesconto, contains('Sub-total'));
      expect(semDesconto, isNot(contains('Desconto')));

      final json = Map<String, Object?>.from(documentJson())
        ..['discount_amount'] = '75.00'
        ..['total_amount'] = '1425.00';

      final comDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );
      expect(comDesconto, contains('Sub-total'));
      expect(comDesconto, contains('Desconto'));
      expect(comDesconto, contains('75,00'));
    });

    test('a linha do item traz o desconto entre colchetes, como no modelo', () {
      final json = Map<String, Object?>.from(documentJson())
        ..['discount_amount'] = '75.00'
        ..['total_amount'] = '1425.00';

      final papel = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );

      expect(papel, contains('[Desconto]'));
      expect(papel, contains('-75,00'));
    });
  });

  group('o papel segue o modelo da nota', () {
    late List<PrintCommand> commands;
    late String papel;

    setUp(() {
      final document = printedDocumentFromJson(documentJson());
      commands = layout.build(document);
      papel = renderCommandsAsText(commands);
    });

    test('os rótulos saem no formato do modelo', () {
      expect(papel, contains('Vendedor:João Silva'));
      expect(papel, contains('VENDA:#10482'));
      expect(papel, contains('REF:DOC1-L1-7F3A9C2B'));
      expect(papel, contains('Data:'));
      expect(papel, contains('Hora:'));
    });

    test('sem cliente, o papel diz isso em vez de omitir a linha', () {
      expect(papel, contains('Cliente:nao informado'));
    });

    test('os itens saem em três colunas, alinhadas com o cabeçalho', () {
      final linhas = papel.split('\n');
      final cabecalho = linhas.firstWhere((l) => l.startsWith('ITEM'));
      final item = linhas.firstWhere((l) => l.startsWith('Pneu Aro 15'));

      // A coluna do valor termina na mesma coluna nas duas linhas: é o que faz
      // o papel ler como tabela, e não como texto desalinhado.
      expect(cabecalho.trimRight().length, item.trimRight().length);
      expect(cabecalho, endsWith('VALOR'));
      expect(item, endsWith('500,00'));
    });

    test('o preço unitário só aparece quando a quantidade não é 1', () {
      // No JSON de referência o primeiro item tem quantidade 2.
      expect(papel, contains('2 x 250,00'));

      final json = Map<String, Object?>.from(documentJson());
      final itens = List<Map<String, Object?>>.from(
        (json['items']! as List<Object?>).cast<Map<String, Object?>>(),
      );
      itens[0] = Map<String, Object?>.from(itens[0])
        ..['quantity'] = '1.000'
        ..['line_total'] = '250.00';
      json['items'] = [itens[0]];

      final umaUnidade = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );
      // Com uma unidade, o unitário é o próprio total — repetir é ruído.
      expect(umaUnidade, isNot(contains('x 250,00')));
    });

    test('a forma de pagamento fecha o bloco do total', () {
      final linhas = papel.split('\n');
      final total = linhas.indexWhere((l) => l.startsWith('Total'));
      final pagamento = linhas.indexWhere((l) => l.startsWith('PIX'));

      expect(total, isNonNegative);
      expect(pagamento, total + 1);
    });

    test('imprime o QR do código da venda, além do código de barras', () {
      final qrs = commands.whereType<PrintQrCode>().toList();

      expect(qrs, hasLength(1));
      expect(qrs.single.data, 'SALE-L1-7F3A9C2B');
    });

    test('agradece no pé, como no modelo', () {
      expect(papel, contains('OBRIGADO! VOLTE SEMPRE!'));
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

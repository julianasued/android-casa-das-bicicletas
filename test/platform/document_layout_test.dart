import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/platform/printer/document_layout.dart';
import 'package:casa_das_bicicletas/platform/printer/print_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const layout = DocumentLayout();

  group('1ª via — nota de conferência (RF08)', () {
    late List<PrintCommand> commands;
    late String papel;

    setUp(() {
      final document = printedDocumentFromJson(documentJson());
      commands = layout.build(document);
      papel = renderCommandsAsText(commands);
    });

    test('traz tudo o que o §7 da integração exige', () {
      // A identificação da empresa é o logo; o nome da loja é o que sai no
      // lugar dele se a imagem falhar.
      final logo = commands.whereType<PrintLogo>().single;
      expect(logo.fallback, 'CASA DAS BICICLETAS CENTRO');
      expect(commands.first, same(logo));

      expect(papel, contains('NOTA DE CONFERÊNCIA'));
      expect(papel, contains('1ª VIA'));
      expect(papel, contains('SALE-L1-7F3A9C2B'));
      expect(papel, contains('João Silva'));
      expect(papel, contains('Pneu Aro 15'));
      expect(papel, contains('PIX'));
      expect(papel, contains('1.500,00'));
    });

    test('manda o cliente ao caixa, em faixa invertida', () {
      // RF12: a 1ª via não é comprovante de pagamento — é o papel que leva o
      // cliente até ele.
      final faixa = commands.whereType<PrintBanner>().single;

      expect(faixa.text, 'LEVE AO CAIXA PARA PAGAMENTO');
    });

    test('imprime o código de barras da venda (RF09)', () {
      final barcodes = commands.whereType<PrintBarcode>().toList();

      expect(barcodes, hasLength(1));
      expect(barcodes.single.data, 'SALE-L1-7F3A9C2B');
    });

    test('os dados da venda saem com o rótulo à esquerda e o valor à direita', () {
      final linhas = papel.split('\n');

      for (final rotulo in ['Venda', 'Data', 'Hora', 'Vendedor', 'Pagamento']) {
        final linha = linhas.firstWhere((l) => l.startsWith(rotulo));
        expect(linha, hasLength(paperColumns), reason: rotulo);
      }
      expect(linhas.firstWhere((l) => l.startsWith('Venda')), endsWith('SALE-L1-7F3A9C2B'));
      expect(linhas.firstWhere((l) => l.startsWith('Vendedor')), endsWith('João Silva'));
    });

    test('o cliente só sai quando a venda tem cliente', () {
      expect(papel, isNot(contains('Cliente')));

      final json = Map<String, Object?>.from(documentJson())
        ..['customer_name'] = 'Maria de Oliveira';
      final comCliente = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );

      expect(comCliente, contains('Maria de Oliveira'));
    });

    test('cada item traz quantidade, unitário e total', () {
      final linhas = papel.split('\n');
      final nome = linhas.indexWhere((l) => l.startsWith('Pneu Aro 15'));

      // No JSON de referência o primeiro item tem quantidade 2.
      expect(linhas[nome + 1], startsWith('  2 x 250,00'));
      expect(linhas[nome + 1], endsWith('500,00'));
      expect(linhas[nome + 1], hasLength(paperColumns));
    });

    test('o total a pagar é o destaque do papel', () {
      final total = commands
          .whereType<PrintText>()
          .singleWhere((c) => c.value.startsWith('TOTAL A PAGAR'));

      expect(total.value, endsWith(r'R$ 1.500,00'));
      expect(total.bold, isTrue);
      expect(total.doubleHeight, isTrue);
    });

    test('o pé diz que o papel é interno e não tem valor fiscal', () {
      expect(papel, contains('Comprovante interno.'));
      expect(papel, contains('Não possui valor fiscal.'));
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
    test('a reimpressão sai marcada no papel (§3.4.3)', () {
      final document = printedDocumentFromJson(
        documentJson(reference: 'DOC1-L1-7F3A9C2B-R2', sequence: 2),
      );
      final papel = renderCommandsAsText(layout.build(document));

      // "1ª VIA" e "2ª VIA" agora nomeiam os dois papéis do fluxo; a
      // reimpressão tem marca própria, com o número dela.
      expect(papel, contains('REIMPRESSÃO 2'));
      expect(papel, contains('1ª VIA'));
    });

    test('o papel original não traz a marca', () {
      final papel = renderCommandsAsText(
        layout.build(printedDocumentFromJson(documentJson())),
      );

      expect(papel, isNot(contains('REIMPRESSÃO')));
    });
  });

  group('2ª via — comprovante de retirada (RF12)', () {
    late List<PrintCommand> commands;
    late String papel;

    setUp(() {
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

      commands = layout.build(printedDocumentFromJson(json));
      papel = renderCommandsAsText(commands);
    });

    test('traz o que o §8 da integração exige', () {
      expect(commands.first, isA<PrintLogo>());
      expect(papel, contains('COMPROVANTE DE RETIRADA'));
      expect(papel, contains('2ª VIA'));
      expect(papel, contains('SALE-L1-7F3A9C2B'));
      expect(papel, contains('Emitido em'));
      expect(papel, contains('João Silva'));
      expect(papel, contains(r'R$ 1.500,00'));
    });

    test('diz em faixa grande que a mercadoria está liberada', () {
      final faixa = commands.whereType<PrintBanner>().single;

      expect(faixa.text, 'MERCADORIA LIBERADA');
      expect(faixa.large, isTrue);
    });

    test('o número da venda sai em destaque', () {
      final venda = commands
          .whereType<PrintText>()
          .firstWhere((c) => c.value == 'SALE-L1-7F3A9C2B');

      expect(venda.bold, isTrue);
      expect(venda.doubleHeight, isTrue);
    });

    test('traz a referência do documento, que a devolução pede (13.4)', () {
      expect(papel, contains('DOC2-L1-7F3A9C2B'));
    });

    test('diz o que fazer com o papel', () {
      expect(papel, contains('ENTREGUE ESTA VIA AO VENDEDOR'));
      expect(papel, contains('PARA RETIRAR A MERCADORIA'));
    });

    test('é curta: não repete os itens nem a conta', () {
      expect(papel, isNot(contains('Pneu Aro 15')));
      expect(papel, isNot(contains('Subtotal')));

      final conferencia = layout.build(printedDocumentFromJson(documentJson()));
      expect(commands.length, lessThan(conferencia.length));
    });

    test('usa o logo pequeno', () {
      expect(commands.whereType<PrintLogo>().single.size, LogoSize.small);
    });

    test('imprime o código de barras da venda', () {
      expect(commands.whereType<PrintBarcode>().single.data, 'SALE-L1-7F3A9C2B');
    });

    test('nenhuma linha ultrapassa a largura da bobina de 2"', () {
      for (final command in commands.whereType<PrintText>()) {
        expect(command.value.length, lessThanOrEqualTo(paperColumns));
      }
    });
  });

  group('desconto', () {
    test('o subtotal sai sempre; o desconto, só quando existe', () {
      // Uma nota que mostra só o total esconde a conta de quem confere no
      // caixa.
      final semDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(documentJson())),
      );
      expect(semDesconto, contains('Subtotal'));
      expect(semDesconto, isNot(contains('Desconto')));

      final json = Map<String, Object?>.from(documentJson())
        ..['discount_amount'] = '75.00'
        ..['total_amount'] = '1425.00';

      final comDesconto = renderCommandsAsText(
        layout.build(printedDocumentFromJson(json)),
      );
      expect(comDesconto, contains('Subtotal'));
      expect(comDesconto, contains('Desconto'));
      expect(comDesconto, contains('-75,00'));
    });
  });

  group('nome que não cabe', () {
    test('nome longo de vendedor é cortado, e a linha não estoura', () {
      final json = Map<String, Object?>.from(documentJson())
        ..['seller_name'] = 'Francisco das Chagas Albuquerque Cavalcanti';

      final commands = layout.build(printedDocumentFromJson(json));
      final vendedor = commands
          .whereType<PrintText>()
          .firstWhere((c) => c.value.startsWith('Vendedor'));

      expect(vendedor.value, hasLength(paperColumns));
      expect(vendedor.value, contains('Francisco das Chagas'));
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

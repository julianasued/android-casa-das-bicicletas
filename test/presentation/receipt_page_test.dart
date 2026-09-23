/// Comprovante no visual de papel térmico — mesmos dados do documento real.
///
/// O que se garante aqui é que a tela não inventa nada: todo texto vem do
/// `PrintedDocument` (o mesmo objeto que a impressora usa) e do percentual de
/// desconto que a Venda Registrada já carrega. Não há asserção sobre pixel de
/// código de barras/QR — isso já é coberto pelos testes de `barcode_bitmap.dart`
/// — só que a tela não quebra ao gerá-los e que o número por extenso aparece.
library;

import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/presentation/receipt/receipt_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  PrintedDocument documento({
    String? customerName,
    String discountAmount = '0.00',
    int sequence = 1,
  }) {
    final json = documentJson(sequence: sequence);
    json['customer_name'] = customerName;
    json['discount_amount'] = discountAmount;
    if (discountAmount != '0.00') {
      json['gross_amount'] = '1000.00';
      json['total_amount'] =
          (1000 - double.parse(discountAmount)).toStringAsFixed(2);
    }
    return printedDocumentFromJson(json);
  }

  Future<void> abrir(
    WidgetTester tester,
    PrintedDocument document, {
    int discountPercentHundredths = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptPage(
          document: document,
          discountPercentHundredths: discountPercentHundredths,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('dados reais da venda', () {
    testWidgets('mostra loja, vendedor, itens, pagamento e total',
        (tester) async {
      await abrir(tester, documento());

      expect(find.text('CASA DAS BICICLETAS CENTRO'), findsOneWidget);
      expect(find.textContaining('Vendedor:João Silva'), findsOneWidget);
      expect(find.textContaining('Cliente:Não informado'), findsOneWidget);
      expect(find.text('Pneu Aro 15'), findsOneWidget);
      expect(find.text('Kit de reparo'), findsOneWidget);
      expect(find.text('R\$ 1.500,00'), findsWidgets); // total, duas vezes
      expect(find.textContaining('PIX'), findsOneWidget);
      expect(find.text('SALE-L1-7F3A9C2B'), findsOneWidget);
    });

    testWidgets('cliente informado aparece pelo nome', (tester) async {
      await abrir(tester, documento(customerName: 'Maria Aparecida'));

      expect(find.textContaining('Cliente:Maria Aparecida'), findsOneWidget);
      expect(find.textContaining('Não informado'), findsNothing);
    });

    testWidgets('o aviso legal do rodapé é o mesmo que sai no papel',
        (tester) async {
      final doc = documento();
      await abrir(tester, doc);

      expect(find.text(doc.notice), findsOneWidget);
      // Nada de recurso inventado: não existe fluxo de avaliação no app.
      expect(find.textContaining('avaliar o atendimento'), findsNothing);
    });

    testWidgets('desconto mostra o critério e o valor negativo',
        (tester) async {
      await abrir(
        tester,
        documento(discountAmount: '50.00'),
        discountPercentHundredths: 500,
      );

      expect(find.textContaining('[Desconto 5% sobre o subtotal]'), findsOneWidget);
      expect(find.text('-R\$ 50,00'), findsWidgets);
    });

    testWidgets('sem desconto, nenhuma linha de desconto aparece',
        (tester) async {
      await abrir(tester, documento());

      expect(find.textContaining('[Desconto'), findsNothing);
      expect(find.text('Desconto'), findsNothing);
    });

    testWidgets('reimpressão mostra a via', (tester) async {
      await abrir(tester, documento(sequence: 2));

      expect(find.textContaining('2ª VIA'), findsOneWidget);
      expect(find.textContaining('REIMPRESSÃO'), findsOneWidget);
    });

    testWidgets('primeira via não mostra marca de reimpressão',
        (tester) async {
      await abrir(tester, documento());

      expect(find.textContaining('VIA'), findsNothing);
    });
  });

  group('não quebra ao gerar os códigos', () {
    testWidgets('renderiza sem exceção', (tester) async {
      await abrir(tester, documento());
      expect(tester.takeException(), isNull);
    });
  });
}

/// Desfecho da venda: o que a tela promete ao vendedor (§14, §15, §16, §17).
///
/// O caso que dá sentido à tela: a venda é registrada e o papel **não** sai —
/// acabou a bobina. A venda vale, o cliente está no balcão, e o que resolve é
/// reimprimir, não refazer. E o caso irmão: a venda ficou na fila porque não há
/// rede, e dizer "pronto" ali seria mentira.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  SaleWithDocument desfecho({String paymentMethod = 'PIX'}) {
    final json = saleJson();
    json['payment_method'] = paymentMethod;
    json['document_1'] = documentJson();
    return saleWithDocumentFromJson(json);
  }

  /// A tela rola: os botões ficam abaixo da dobra depois dos cartões de
  /// estado, e a ListView não constrói o que não está visível.
  Future<void> rolarAte(WidgetTester tester, Finder alvo) async {
    await tester.scrollUntilVisible(
      alvo,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> montar(
    WidgetTester tester,
    SaleFinished finished, {
    RecordingTransport? transport,
  }) async {
    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: transport),
        child: MaterialApp(
          home: SaleFinishedPage(finished: finished),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('venda finalizada (§14)', () {
    testWidgets('anuncia o desfecho e os dados da venda', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(find.text('VENDA FINALIZADA!'), findsOneWidget);
      expect(find.textContaining('Venda #'), findsOneWidget);
      expect(find.text('SALE-L1-7F3A9C2B'), findsOneWidget);
      expect(find.text('Vendedor'), findsOneWidget);
      expect(find.text('Pagamento'), findsOneWidget);
    });

    testWidgets('voltar ao início leva à venda, não ao menu antigo',
        (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      await rolarAte(tester, find.text('Voltar ao início'));
      await tester.tap(find.text('Voltar ao início'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
    });
  });

  group('impressão (§15)', () {
    testWidgets('impressão bem-sucedida orienta a entregar o documento',
        (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(find.textContaining('impresso'), findsWidgets);
    });

    testWidgets('falha de impressão não apaga a venda e oferece reimprimir',
        (tester) async {
      await montar(
        tester,
        SaleFinished(
          result: desfecho(),
          printFailure: const OutOfPaperFailure(),
        ),
      );

      // A venda continua na tela: ela vale, o que faltou foi o papel.
      expect(find.text('VENDA FINALIZADA!'), findsOneWidget);
      expect(find.textContaining('não foi impresso'), findsOneWidget);
      await rolarAte(tester, find.text('Reimprimir documento 1'));
      expect(find.text('Reimprimir documento 1'), findsOneWidget);
    });

    testWidgets('reimprimir usa a reimpressão, e não gera outra venda',
        (tester) async {
      final transport = RecordingTransport((request) {
        if (request.url.path.contains('document-1/print')) {
          return jsonResponse(documentJson(sequence: 2));
        }
        return jsonResponse(const <String, Object?>{});
      });

      await montar(
        tester,
        SaleFinished(
          result: desfecho(),
          printFailure: const OutOfPaperFailure(),
        ),
        transport: transport,
      );

      await rolarAte(tester, find.text('Reimprimir documento 1'));
      await tester.tap(find.text('Reimprimir documento 1'));
      await tester.pumpAndSettle();

      // Nenhum POST /sales/: reimpressão não duplica venda nem documento.
      expect(
        transport.requests.any(
          (r) => r.method == 'POST' && r.url.path.endsWith('/sales/'),
        ),
        isFalse,
      );
      expect(
        transport.requests.any((r) => r.url.path.contains('document-1/print')),
        isTrue,
      );
    });
  });

  group('documento (§16)', () {
    testWidgets('venda à vista lembra que o documento vai ao caixa',
        (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(find.textContaining('Não esqueça de entregar'), findsOneWidget);
      // Documento 1 não é comprovante de pagamento (RF08).
      expect(
        find.textContaining('não é comprovante de pagamento'),
        findsOneWidget,
      );
    });

    testWidgets('notinha tem lembrete próprio', (tester) async {
      await montar(
        tester,
        SaleFinished(result: desfecho(paymentMethod: 'NOTINHA')),
      );

      expect(
        find.textContaining('entregar a notinha para o cliente'),
        findsOneWidget,
      );
    });
  });

  group('offline (§17)', () {
    testWidgets('venda na fila não se passa por sincronizada', (tester) async {
      await montar(
        tester,
        SaleFinished(
          result: desfecho(),
          pendingOperationId: '7f3a9c2b-1111-4222-8333-444455556666',
        ),
      );

      expect(
        find.text('Registrada no terminal, ainda não enviada'),
        findsOneWidget,
      );
      expect(find.textContaining('sobe sozinha'), findsOneWidget);
    });

    testWidgets('venda enviada não mostra aviso de fila', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(
        find.text('Registrada no terminal, ainda não enviada'),
        findsNothing,
      );
    });
  });
}

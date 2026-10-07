/// Confirmação de que o caixa recebeu a venda (§ Parte 6, RF10–RF12).
///
/// O terminal do vendedor **não** recebe pagamento: quem recebe é o caixa, em
/// outra estação, com permissão própria. O que esta tela faz é perguntar ao
/// servidor o que já foi registrado — e é por isso que ela pode ser usada com
/// o cliente esperando no balcão sem risco de duplicar nada.
///
/// O que se garante aqui: a confirmação só aparece quando o pagamento existe,
/// conferir não grava coisa alguma, e daí se continua para a próxima venda.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  /// Servidor que responde a consulta da venda com o `status` pedido.
  RecordingTransport servidor(String status) => RecordingTransport(
        (_) => jsonResponse(saleJson(status: status, withDocument: false)),
      );

  Future<AppDependencies> montar(
    WidgetTester tester,
    RecordingTransport http,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final deps = buildTestDependencies(transport: http);
    final json = saleJson();
    json['document_1'] = documentJson();

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: MaterialApp(
          home: SaleFinishedPage(
            finished: SaleFinished(result: saleWithDocumentFromJson(json)),
          ),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('rota: ${settings.name}')),
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return deps;
  }

  Future<void> conferir(WidgetTester tester) async {
    await tester.ensureVisible(find.text('CONFERIR PAGAMENTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFERIR PAGAMENTO'));
    await tester.pumpAndSettle();
  }

  group('a confirmação não aparece antes do pagamento', () {
    testWidgets('a venda registrada não anuncia pagamento', (tester) async {
      await montar(tester, servidor('AGUARDANDO_CAIXA'));

      // Ao finalizar, o cliente nem foi ao caixa: dizer "pagamento
      // confirmado" aqui seria afirmar o que não aconteceu.
      expect(find.text('PAGAMENTO CONFIRMADO'), findsNothing);
      expect(find.text('Aguardando caixa'), findsOneWidget);
    });

    testWidgets('conferir antes de pagar explica o que falta', (tester) async {
      await montar(tester, servidor('AGUARDANDO_CAIXA'));
      await conferir(tester);

      expect(find.text('PAGAMENTO CONFIRMADO'), findsNothing);
      expect(
        find.textContaining('Ainda não foi recebida no caixa'),
        findsOneWidget,
      );
    });
  });

  group('pagamento aprovado', () {
    testWidgets('confirmação exibida quando o caixa recebeu', (tester) async {
      await montar(tester, servidor('PAGA'));
      await conferir(tester);

      expect(find.text('PAGAMENTO CONFIRMADO'), findsOneWidget);
      expect(find.text('Venda finalizada com sucesso.'), findsOneWidget);
      // A tela de baixo saiu do caminho: um toque em NOVA VENDA não fica
      // ambíguo entre as duas rotas.
      expect(find.text('NOVA VENDA'), findsOneWidget);
      expect(find.text('CONFERIR PAGAMENTO'), findsNothing);
      // O número da venda fica à vista: é o que se confere com o papel.
      expect(find.text('SALE-L1-7F3A9C2B'), findsWidgets);
    });

    testWidgets('notinha não é anunciada como pagamento', (tester) async {
      await montar(tester, servidor('PENDENTE_NOTINHA'));
      await conferir(tester);

      // O caixa conferiu, mas é fiado: ninguém pagou nada. Anunciar
      // pagamento aqui diria ao vendedor que entrou dinheiro que não entrou.
      expect(find.text('PAGAMENTO CONFIRMADO'), findsNothing);
      expect(find.text('CONFIRMADO NO CAIXA'), findsOneWidget);
      expect(
        find.textContaining('o valor fica em aberto'),
        findsOneWidget,
      );
    });

    testWidgets('venda cancelada não vira tela de sucesso', (tester) async {
      await montar(tester, servidor('CANCELADA'));
      await conferir(tester);

      expect(find.text('PAGAMENTO CONFIRMADO'), findsNothing);
      expect(find.textContaining('Cancelada'), findsOneWidget);
    });
  });

  group('não duplica nada', () {
    testWidgets('conferir é leitura: nenhum POST sai do aparelho',
        (tester) async {
      final http = servidor('PAGA');
      await montar(tester, http);
      await conferir(tester);

      // Nem recebimento, nem uma segunda venda: só a consulta.
      expect(http.requests.every((r) => r.method == 'GET'), isTrue);
      expect(
        http.requests.any((r) => r.url.path.contains('cash/payments')),
        isFalse,
      );
      expect(
        http.requests.any((r) => r.method == 'POST' && r.url.path.endsWith('/sales/')),
        isFalse,
      );
    });

    testWidgets('conferir de novo não cria uma segunda venda', (tester) async {
      final http = servidor('PAGA');
      await montar(tester, http);

      await conferir(tester);
      await tester.tap(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();

      // Só consultas da mesma venda, quantas vezes forem.
      final consultas =
          http.requests.where((r) => r.url.path.contains('/sales/10482/'));
      expect(consultas, isNotEmpty);
      expect(http.requests.every((r) => r.method == 'GET'), isTrue);
    });
  });

  group('continuidade', () {
    testWidgets('da confirmação segue para a nova venda', (tester) async {
      await montar(tester, servidor('PAGA'));
      await conferir(tester);

      await tester.tap(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
    });

    testWidgets('da confirmação também dá para encerrar', (tester) async {
      await montar(tester, servidor('PAGA'));
      await conferir(tester);

      await tester.tap(find.text('INÍCIO'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /inicial'), findsOneWidget);
    });
  });
}

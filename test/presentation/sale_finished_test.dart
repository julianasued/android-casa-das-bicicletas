/// Desfecho da venda: o que a tela promete ao vendedor (§14, §15, §16, §17).
///
/// O caso que dá sentido à tela: a venda é registrada e o papel **não** sai —
/// acabou a bobina. A venda vale, o cliente está no balcão, e o que resolve é
/// reimprimir, não refazer. E o caso irmão: a venda ficou na fila porque não há
/// rede, e dizer "pronto" ali seria mentira.
library;

import 'dart:io';

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/printed_document.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_queue.dart';
import 'package:casa_das_bicicletas/domain/usecases/create_sale.dart';
import 'package:casa_das_bicicletas/presentation/sale/sale_finished_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  SaleWithDocument desfecho({String paymentMethod = 'PIX', int id = 10482}) {
    final json = saleJson(id: id);
    json['payment_method'] = paymentMethod;
    json['document_1'] = documentJson();
    return saleWithDocumentFromJson(json);
  }

  /// A venda offline como ela é de fato: `id` zero.
  ///
  /// O autoincremento é do servidor, e `OfflineSaleContext.localSale` monta a
  /// venda local com zero justamente por isso. Combinar um id de servidor com
  /// `pendingOperationId` — como este teste fazia — descreve um estado que a
  /// produção não produz, e era o que escondia o `404` do OFF-013.
  SaleFinished desfechoNaFila() => SaleFinished(
        result: desfecho(id: 0),
        pendingOperationId: '7f3a9c2b-1111-4222-8333-444455556666',
      );

  /// Em tela estreita o miolo rola; as duas saídas ficam fixas no pé.
  Future<void> rolarAte(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
  }

  Future<void> montar(
    WidgetTester tester,
    SaleFinished finished, {
    RecordingTransport? transport,
    SyncQueue? fila,
  }) async {
    await tester.pumpWidget(
      DependenciesScope(
        dependencies: buildTestDependencies(transport: transport, syncQueue: fila),
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

      expect(find.text('VENDA FINALIZADA'), findsOneWidget);
      expect(find.textContaining('Venda #'), findsOneWidget);
      expect(find.text('SALE-L1-7F3A9C2B'), findsOneWidget);
      expect(find.text('VENDEDOR'), findsOneWidget);
      expect(find.text('PAGAMENTO'), findsOneWidget);
      // A situação é a que o servidor registrou. A tela não declara a venda
      // paga em lugar nenhum: quem recebe é o caixa, e o estado só muda lá.
      expect(find.text('Aguardando caixa'), findsOneWidget);
      expect(find.text('Paga'), findsNothing);
      expect(find.textContaining('venda paga'), findsNothing);
    });

    testWidgets('INÍCIO leva ao repouso do terminal', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      await rolarAte(tester, find.text('INÍCIO'));
      await tester.tap(find.text('INÍCIO'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /inicial'), findsOneWidget);
    });

    testWidgets('NOVA VENDA abre outra montagem, do zero', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      await rolarAte(tester, find.text('NOVA VENDA'));
      await tester.tap(find.text('NOVA VENDA'));
      await tester.pumpAndSettle();

      expect(find.text('rota: /venda'), findsOneWidget);
    });

    testWidgets('sem cliente, a tela diz isso em vez de omitir', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(find.text('Venda sem cliente'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
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
      expect(find.text('VENDA FINALIZADA'), findsOneWidget);
      expect(find.textContaining('não foi impresso'), findsOneWidget);
      await rolarAte(tester, find.text('REIMPRIMIR DOCUMENTO'));
      expect(find.text('REIMPRIMIR DOCUMENTO'), findsOneWidget);
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

      await rolarAte(tester, find.text('REIMPRIMIR DOCUMENTO'));
      await tester.tap(find.text('REIMPRIMIR DOCUMENTO'));
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

  group('reimpressão com resposta perdida (OFF-014)', () {
    testWidgets('o terminal não afirma que a via não foi registrada', (tester) async {
      // A rota é propositalmente não idempotente: cada pedido gera uma via nova
      // e numerada (§3.4.3). Então resposta perdida **não** significa que nada
      // aconteceu — pode ter sido registrada. Dizer "a operação não foi
      // enviada", como a falha genérica diz, é afirmar o que não se sabe, e
      // insistir às cegas registra uma via a mais do que o papel que existe.
      final transporte = RecordingTransport((request) {
        if (request.url.path.contains('document-1/print')) {
          throw const SocketException('conexão caiu depois do envio');
        }
        return jsonResponse(const <String, Object?>{});
      });

      await montar(
        tester,
        SaleFinished(
          result: desfecho(),
          printFailure: const OutOfPaperFailure(),
        ),
        transport: transporte,
      );

      await rolarAte(tester, find.text('REIMPRIMIR DOCUMENTO'));
      await tester.tap(find.text('REIMPRIMIR DOCUMENTO'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Não deu para confirmar'), findsOneWidget);
      expect(find.textContaining('Veja se o papel saiu'), findsOneWidget);
      // O que a falha genérica afirmaria, e que aqui seria mentira.
      expect(find.textContaining('não foi enviada'), findsNothing);
    });

    testWidgets('a via mostrada não avança no escuro', (tester) async {
      // Sem resposta não há número: o contador da tela sai do `sequence` que o
      // servidor registrou, nunca de um incremento local.
      final transporte = RecordingTransport((request) {
        if (request.url.path.contains('document-1/print')) {
          throw const SocketException('conexão caiu depois do envio');
        }
        return jsonResponse(const <String, Object?>{});
      });

      await montar(
        tester,
        SaleFinished(result: desfecho()),
        transport: transporte,
      );

      await rolarAte(tester, find.text('REIMPRIMIR DOCUMENTO'));
      await tester.tap(find.text('REIMPRIMIR DOCUMENTO'));
      await tester.pumpAndSettle();

      expect(find.text('REIMPRIMIR DOCUMENTO (2)'), findsNothing);
    });
  });

  group('documento (§16)', () {
    testWidgets('venda à vista lembra que o documento vai ao caixa',
        (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(
        find.textContaining('Entregue ao cliente para levar ao caixa'),
        findsOneWidget,
      );
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
      await montar(tester, desfechoNaFila());

      expect(
        find.text('Registrada no terminal, ainda não enviada'),
        findsOneWidget,
      );
      expect(find.textContaining('sobe sozinha'), findsOneWidget);
    });

    testWidgets('na fila, as duas ações do servidor ficam fora de alcance', (tester) async {
      // O achado: a venda offline tem `id` zero, e os dois botões chamavam
      // `/sales/0/` — 404 com o cliente no balcão (OFF-013).
      await montar(tester, desfechoNaFila(), fila: _FilaDaVenda());

      final conferir = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('CONFERIR PAGAMENTO'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(conferir.onPressed, isNull);
      expect(
        find.textContaining('só depois que ela subir'),
        findsOneWidget,
      );
    });

    testWidgets('depois de subir, a tela adota o número do servidor', (tester) async {
      // O papel promete isto em letras: "o numero do documento sai na
      // reimpressao, depois da sincronizacao". Quem sabe o número é a fila, que
      // o guardou quando o lote voltou aceito.
      await montar(
        tester,
        desfechoNaFila(),
        fila: _FilaDaVenda(
          operacao: _operacaoSincronizada(serverId: 10490),
        ),
      );

      expect(find.text('Enviada ao servidor'), findsOneWidget);
      expect(find.textContaining('Venda #10490'), findsOneWidget);

      final conferir = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('CONFERIR PAGAMENTO'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(conferir.onPressed, isNotNull);
    });

    testWidgets('JÁ SUBIU? relê a fila e libera as ações', (tester) async {
      // O vendedor está com o cliente na frente, e a rede pode ter voltado nos
      // últimos segundos.
      final fila = _FilaDaVenda();
      await montar(tester, desfechoNaFila(), fila: fila);

      expect(find.textContaining('ainda não enviada'), findsOneWidget);

      fila.operacao = _operacaoSincronizada(serverId: 10491);
      await rolarAte(tester, find.text('JÁ SUBIU?'));
      await tester.tap(find.text('JÁ SUBIU?'));
      await tester.pumpAndSettle();

      expect(find.text('Enviada ao servidor'), findsOneWidget);
      expect(find.text('JÁ SUBIU?'), findsNothing);
      expect(fila.consultas, 2);
    });

    testWidgets('operação em conflito diz que espera decisão, não que vai subir', (tester) async {
      await montar(
        tester,
        desfechoNaFila(),
        fila: _FilaDaVenda(
          operacao: _operacao(status: SyncStatus.conflitante, serverId: null),
        ),
      );

      expect(find.text('Travou na sincronização'), findsOneWidget);
      expect(find.textContaining('decisão do gerente'), findsOneWidget);
    });

    testWidgets('recusa manda o vendedor ao lugar onde está o motivo', (tester) async {
      await montar(
        tester,
        desfechoNaFila(),
        fila: _FilaDaVenda(
          operacao: _operacao(status: SyncStatus.erro, serverId: null),
        ),
      );

      expect(find.text('O servidor recusou o envio'), findsOneWidget);
      expect(find.textContaining('SINCRONIZAÇÃO, no menu'), findsOneWidget);
    });

    testWidgets('sem id do servidor, nunca sai requisição para /sales/0/', (tester) async {
      final transporte = RecordingTransport.empty();
      await montar(
        tester,
        desfechoNaFila(),
        transport: transporte,
        fila: _FilaDaVenda(),
      );

      await rolarAte(tester, find.text('CONFERIR PAGAMENTO'));
      await tester.tap(find.text('CONFERIR PAGAMENTO'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(transporte.requests, isEmpty);
    });

    testWidgets('venda enviada não mostra aviso de fila', (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      expect(
        find.text('Registrada no terminal, ainda não enviada'),
        findsNothing,
      );
    });
  });

  group('comprovante (visual de papel térmico)', () {
    testWidgets('VER COMPROVANTE abre a tela no visual da nota impressa',
        (tester) async {
      await montar(tester, SaleFinished(result: desfecho()));

      await rolarAte(tester, find.text('VER COMPROVANTE'));
      await tester.tap(find.text('VER COMPROVANTE'));
      await tester.pumpAndSettle();

      // A mesma referência que saiu (ou vai sair) no papel — não um número
      // recalculado por esta tela.
      expect(find.text('SALE-L1-7F3A9C2B'), findsOneWidget);
      expect(find.textContaining('Vendedor:'), findsOneWidget);
    });

    testWidgets('sem documento, o botão não aparece', (tester) async {
      final semDocumento = saleWithDocumentFromJson(
        saleJson()..remove('document_1'),
      );
      await montar(tester, SaleFinished(result: semDocumento));

      expect(find.text('VER COMPROVANTE'), findsNothing);
    });
  });
}


PendingOperation _operacao({required SyncStatus status, int? serverId}) =>
    PendingOperation(
      operationId: '7f3a9c2b-1111-4222-8333-444455556666',
      type: OperationType.saleCreate,
      payload: const {'uuid': '7f3a9c2b-1111-4222-8333-444455556666'},
      occurredAt: DateTime(2026, 10, 10, 14, 32),
      status: status,
      serverId: serverId,
    );

PendingOperation _operacaoSincronizada({required int serverId}) =>
    _operacao(status: SyncStatus.sincronizado, serverId: serverId);

/// Fila que só sabe responder por esta venda.
class _FilaDaVenda implements SyncQueue {
  _FilaDaVenda({this.operacao});

  /// O que a fila devolve na consulta — nulo significa "não está mais lá".
  PendingOperation? operacao;

  int consultas = 0;

  @override
  Future<PendingOperation?> find(String operationId) async {
    consultas++;
    return operacao ?? _operacao(status: SyncStatus.pendente, serverId: null);
  }

  @override
  Future<void> enqueue(PendingOperation operation) async {}

  @override
  Future<QueueSummary> summary() async =>
      const QueueSummary(pending: 1, failed: 0, conflicting: 0);

  @override
  Future<List<PendingOperation>> needingAttention() async => const [];
}

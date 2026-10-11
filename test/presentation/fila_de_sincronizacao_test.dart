/// A tela da fila de sincronização — OFF-008.
///
/// O que se garante: os três estados aparecem **separados**, o motivo que o
/// servidor deu aparece em vez de "erro", o conflito diz que espera gente, e o
/// botão de enviar existe e só funciona com rede.
///
/// Antes disso o terminal tinha tudo e mostrava nada: `syncNow()` documentado
/// como "a tela precisa disto" e nenhuma tela chamando, `needingAttention()`
/// nunca chamado, e o rodapé somando os três estados num número único.
library;

import 'package:casa_das_bicicletas/app/dependencies.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/reference_snapshot.dart';
import 'package:casa_das_bicicletas/domain/entities/sync_outcome.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_queue.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_repository.dart';
import 'package:casa_das_bicicletas/domain/usecases/sync_pending_operations.dart';
import 'package:casa_das_bicicletas/platform/connectivity/connectivity_channel.dart';
import 'package:casa_das_bicicletas/platform/connectivity/sync_scheduler.dart';
import 'package:casa_das_bicicletas/presentation/sync/fila_de_sincronizacao_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

PendingOperation _operacao({
  required String id,
  required SyncStatus status,
  String? erro,
  int tentativas = 1,
  String? conflito,
}) =>
    PendingOperation(
      operationId: id,
      type: OperationType.saleCreate,
      payload: const {'uuid': 'x'},
      occurredAt: DateTime(2026, 10, 9, 14, 32),
      status: status,
      attempts: tentativas,
      lastError: erro,
      conflictId: conflito,
    );

/// Fila em memória: o que se testa é a tela, não o SQL.
class _FilaFalsa implements SyncQueue, SyncableQueue {
  _FilaFalsa({
    this.resumo = const QueueSummary(pending: 0, failed: 0, conflicting: 0),
    this.travadas = const [],
  });

  QueueSummary resumo;
  List<PendingOperation> travadas;
  List<PendingOperation> lote = const [];

  int envios = 0;

  @override
  Future<void> enqueue(PendingOperation operation) async {}

  @override
  Future<QueueSummary> summary() async => resumo;

  @override
  Future<List<PendingOperation>> needingAttention() async => travadas;

  @override
  Future<PendingOperation?> find(String operationId) async => null;

  @override
  Future<List<PendingOperation>> nextBatch({int limit = 50}) async {
    envios++;
    return lote;
  }

  @override
  Future<void> markSynced(String operationId, {int? serverId}) async {}

  @override
  Future<void> markFailed(String operationId, String error) async {}

  @override
  Future<void> markConflicting(
    String operationId, {
    String? conflictId,
    String? error,
  }) async {}

  @override
  Future<int> pruneSynced({Duration keepFor = const Duration(days: 7)}) async => 0;
}

class _RepoFalso implements SyncRepository {
  List<SyncOutcome> desfechos = const [];

  @override
  Future<Result<List<SyncOutcome>>> push(List<PendingOperation> operations) async =>
      Ok(desfechos);

  @override
  Future<Result<ReferenceSnapshot>> pull({DateTime? since, String? cursor}) async =>
      Ok(ReferenceSnapshot(syncedAt: DateTime(2026, 10, 9)));
}

void main() {
  Future<AppDependencies> abrir(
    WidgetTester tester, {
    required _FilaFalsa fila,
    _RepoFalso? repo,
    bool online = true,
  }) async {
    final agendador = SyncScheduler(
      // Instância própria e nunca iniciada: o agendador só usa a conexão nos
      // gatilhos automáticos, e `syncNow()` é o caminho do botão. Quem decide
      // se o botão está disponível é a conexão das dependências.
      connectivity: ConnectivityChannel(),
      sync: SyncPendingOperations(queue: fila, sync: repo ?? _RepoFalso()),
    );

    final deps = buildTestDependencies(
      syncQueue: fila,
      syncScheduler: agendador,
      online: online,
    );
    addTearDown(agendador.dispose);
    await deps.connectivity.start();

    await tester.pumpWidget(
      DependenciesScope(
        dependencies: deps,
        child: const MaterialApp(home: FilaDeSincronizacaoPage()),
      ),
    );
    await tester.pumpAndSettle();
    return deps;
  }

  group('os contadores', () {
    testWidgets('mostram os três estados separados', (tester) async {
      // O ponto do achado: somados, "6 operações esperando envio" juntava o que
      // sobe sozinho com o que nunca sobe sem decisão de gente.
      await abrir(
        tester,
        fila: _FilaFalsa(
          resumo: const QueueSummary(pending: 3, failed: 2, conflicting: 1),
        ),
      );

      expect(find.text('ESPERANDO ENVIO'), findsOneWidget);
      expect(find.text('RECUSADAS'), findsOneWidget);
      expect(find.text('EM CONFLITO'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('dizem de quando é a mais antiga', (tester) async {
      await abrir(
        tester,
        fila: _FilaFalsa(
          resumo: QueueSummary(
            pending: 1,
            failed: 0,
            conflicting: 0,
            oldestPendingAt: DateTime(2026, 10, 7, 9, 15),
          ),
        ),
      );

      expect(find.textContaining('A mais antiga esperando'), findsOneWidget);
    });
  });

  group('o que travou', () {
    testWidgets('mostra o motivo que o servidor deu, não "erro"', (tester) async {
      // A frase só existe aqui porque o OFF-007 passou a lê-la de
      // `error.message`; antes a fila guardava a genérica.
      await abrir(
        tester,
        fila: _FilaFalsa(
          resumo: const QueueSummary(pending: 0, failed: 1, conflicting: 0),
          travadas: [
            _operacao(
              id: 'a',
              status: SyncStatus.erro,
              erro: 'Produto 10 inativo ou de outra loja.',
              tentativas: 3,
            ),
          ],
        ),
      );

      expect(find.text('Produto 10 inativo ou de outra loja.'), findsOneWidget);
      expect(find.textContaining('Será tentada de novo'), findsOneWidget);
      expect(find.textContaining('3 tentativas'), findsOneWidget);
    });

    testWidgets('conflito diz que espera decisão, e não que vai tentar de novo', (tester) async {
      // 13.11 — insistir produziria o mesmo conflito. A diferença entre os dois
      // estados é o que o operador precisa saber para não ficar esperando.
      await abrir(
        tester,
        fila: _FilaFalsa(
          resumo: const QueueSummary(pending: 0, failed: 0, conflicting: 1),
          travadas: [
            _operacao(
              id: 'b',
              status: SyncStatus.conflitante,
              erro: 'Hora do evento fora da janela: 400 dias atrás.',
              conflito: '42',
            ),
          ],
        ),
      );

      expect(find.textContaining('Espera decisão'), findsOneWidget);
      expect(find.textContaining('Será tentada de novo'), findsNothing);
      expect(find.text('Hora do evento fora da janela: 400 dias atrás.'), findsOneWidget);
    });

    testWidgets('nada travado não vira lista vazia sem explicação', (tester) async {
      await abrir(tester, fila: _FilaFalsa());

      expect(find.textContaining('Nada travado'), findsOneWidget);
    });
  });

  group('o envio manual', () {
    testWidgets('com rede, o botão envia a fila e conta o desfecho', (tester) async {
      final fila = _FilaFalsa(
        resumo: const QueueSummary(pending: 1, failed: 0, conflicting: 0),
      )..lote = [_operacao(id: 'c', status: SyncStatus.pendente)];
      final repo = _RepoFalso()
        ..desfechos = [
          const SyncOutcome(
            operationId: 'c',
            status: SyncStatus.sincronizado,
            serverId: 10490,
          ),
        ];

      await abrir(tester, fila: fila, repo: repo);
      await tester.tap(find.text('SINCRONIZAR AGORA'));
      await tester.pumpAndSettle();

      expect(fila.envios, 1);
      expect(find.textContaining('1 aceitas'), findsOneWidget);
    });

    testWidgets('sem rede, o botão não funciona e a tela diz por quê', (tester) async {
      final fila = _FilaFalsa(
        resumo: const QueueSummary(pending: 2, failed: 0, conflicting: 0),
      );

      await abrir(tester, fila: fila, online: false);

      final botao = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(botao.onPressed, isNull);
      expect(find.textContaining('Sem rede agora'), findsOneWidget);

      await tester.tap(find.text('SINCRONIZAR AGORA'));
      await tester.pumpAndSettle();
      expect(fila.envios, 0);
    });
  });
}

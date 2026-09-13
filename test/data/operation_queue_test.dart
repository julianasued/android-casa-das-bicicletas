/// A fila de operações pendentes (RF35), contra SQLite de verdade.
///
/// O que está na fila já aconteceu no balcão: o papel saiu e o cliente foi
/// embora. Então o que estes testes cobram é **não perder** e **não duplicar** —
/// e a ordem, porque o servidor precisa ver a venda antes do pagamento dela.
library;

import 'package:casa_das_bicicletas/data/local/local_database.dart';
import 'package:casa_das_bicicletas/data/local/operation_queue.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PendingOperation _venda({
  String id = 'op-1',
  DateTime? quando,
  Map<String, Object?>? payload,
  SyncStatus status = SyncStatus.pendente,
}) =>
    PendingOperation(
      operationId: id,
      type: OperationType.saleCreate,
      payload: payload ?? {'uuid': id, 'payment_method': 'PIX'},
      occurredAt: quando ?? DateTime.utc(2026, 9, 11, 14, 30),
      status: status,
    );

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late OperationQueue fila;

  setUp(() {
    db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    fila = OperationQueue(db);
  });

  tearDown(() => db.close());

  group('entrar na fila', () {
    test('guarda e devolve a operação inteira', () async {
      await fila.enqueue(_venda(payload: {'uuid': 'abc', 'total': '1500.00'}));

      final guardada = await fila.find('op-1');
      expect(guardada, isNotNull);
      expect(guardada!.type, OperationType.saleCreate);
      expect(guardada.payload['uuid'], 'abc');
      expect(guardada.payload['total'], '1500.00');
      expect(guardada.status, SyncStatus.pendente);
      expect(guardada.attempts, 0);
      expect(guardada.occurredAt, DateTime.utc(2026, 9, 11, 14, 30));
    });

    test('a mesma operação duas vezes não duplica nem sobrescreve', () async {
      // O payload gravado é o que o papel do cliente reflete; uma segunda
      // tentativa não deve substituí-lo.
      await fila.enqueue(_venda(payload: {'total': '1500.00'}));
      await fila.enqueue(_venda(payload: {'total': '9999.00'}));

      final lote = await fila.nextBatch();
      expect(lote, hasLength(1));
      expect(lote.single.payload['total'], '1500.00');
    });

    test('payload com acento e aspas sobrevive ao JSON', () async {
      await fila.enqueue(
        _venda(payload: {'obs': "Cliente pediu 2 câmaras d'ar"}),
      );

      final guardada = await fila.find('op-1');
      expect(guardada!.payload['obs'], "Cliente pediu 2 câmaras d'ar");
    });
  });

  group('próximo lote', () {
    test('sai na ordem em que aconteceu, não na de gravação', () async {
      // O servidor precisa ver a venda antes do pagamento dela.
      await fila.enqueue(
        _venda(id: 'depois', quando: DateTime.utc(2026, 9, 11, 18)),
      );
      await fila.enqueue(
        _venda(id: 'antes', quando: DateTime.utc(2026, 9, 11, 9)),
      );

      final lote = await fila.nextBatch();
      expect(lote.map((op) => op.operationId), ['antes', 'depois']);
    });

    test('inclui as que falharam, porque a causa costuma passar', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markFailed('op-1', 'timeout');

      final lote = await fila.nextBatch();
      expect(lote, hasLength(1));
      expect(lote.single.status, SyncStatus.erro);
    });

    test('exclui conflitante: insistir daria o mesmo conflito', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markConflicting('op-1', conflictId: 'cf-1');

      expect(await fila.nextBatch(), isEmpty);
    });

    test('exclui o que já foi sincronizado', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markSynced('op-1', serverId: 10490);

      expect(await fila.nextBatch(), isEmpty);
    });

    test('respeita o limite do lote', () async {
      for (var i = 0; i < 5; i++) {
        await fila.enqueue(
          _venda(id: 'op-$i', quando: DateTime.utc(2026, 9, 11, 10, i)),
        );
      }

      expect(await fila.nextBatch(limit: 2), hasLength(2));
    });
  });

  group('desfechos', () {
    test('sincronizada guarda o id do servidor e limpa o erro', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markFailed('op-1', 'timeout');
      await fila.markSynced('op-1', serverId: 10490);

      final guardada = await fila.find('op-1');
      expect(guardada!.status, SyncStatus.sincronizado);
      expect(guardada.serverId, 10490);
      expect(guardada.lastError, isNull);
      expect(guardada.syncedAt, isNotNull);
    });

    test('cada falha conta uma tentativa', () async {
      // Sete tentativas falhando é outro problema que a primeira, e a tela
      // precisa poder dizer isso.
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markFailed('op-1', 'timeout');
      await fila.markFailed('op-1', 'timeout de novo');

      final guardada = await fila.find('op-1');
      expect(guardada!.attempts, 2);
      expect(guardada.lastError, 'timeout de novo');
    });

    test('conflito guarda o identificador para a decisão', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markConflicting(
        'op-1',
        conflictId: 'cf-uuid-1',
        error: 'Venda já confirmada no servidor',
      );

      final guardada = await fila.find('op-1');
      expect(guardada!.status, SyncStatus.conflitante);
      expect(guardada.conflictId, 'cf-uuid-1');
      expect(guardada.status.needsDecision, isTrue);
      expect(guardada.status.shouldRetry, isFalse);
    });
  });

  group('resumo para a tela', () {
    test('fila vazia é vazia', () async {
      final resumo = await fila.summary();
      expect(resumo.isEmpty, isTrue);
      expect(resumo.outstanding, 0);
      expect(resumo.oldestPendingAt, isNull);
    });

    test('conta cada situação separadamente', () async {
      await fila.enqueue(_venda(id: 'p1'));
      await fila.enqueue(_venda(id: 'p2'));
      await fila.enqueue(_venda(id: 'e1'));
      await fila.markFailed('e1', 'erro');
      await fila.enqueue(_venda(id: 'c1'));
      await fila.markConflicting('c1');
      await fila.enqueue(_venda(id: 's1'));
      await fila.markSynced('s1');

      final resumo = await fila.summary();
      expect(resumo.pending, 2);
      expect(resumo.failed, 1);
      expect(resumo.conflicting, 1);
      // Sincronizada não conta: já chegou.
      expect(resumo.outstanding, 4);
      expect(resumo.isEmpty, isFalse);
    });

    test('diz qual é a mais antiga esperando', () async {
      // Uma venda de dez minutos é normal; de três dias, alguém precisa saber.
      await fila.enqueue(
        _venda(id: 'nova', quando: DateTime.utc(2026, 9, 11, 18)),
      );
      await fila.enqueue(
        _venda(id: 'antiga', quando: DateTime.utc(2026, 9, 8, 9)),
      );

      final resumo = await fila.summary();
      expect(resumo.oldestPendingAt, DateTime.utc(2026, 9, 8, 9));
    });

    test('a mais antiga ignora o que já sincronizou', () async {
      await fila.enqueue(
        _venda(id: 'antiga', quando: DateTime.utc(2026, 9, 8, 9)),
      );
      await fila.enqueue(
        _venda(id: 'nova', quando: DateTime.utc(2026, 9, 11, 18)),
      );
      await fila.markSynced('antiga');

      final resumo = await fila.summary();
      expect(resumo.oldestPendingAt, DateTime.utc(2026, 9, 11, 18));
    });
  });

  group('o que precisa de gente', () {
    test('lista conflito e erro, não o que está só esperando', () async {
      await fila.enqueue(_venda(id: 'p1'));
      await fila.enqueue(_venda(id: 'e1'));
      await fila.markFailed('e1', 'erro');
      await fila.enqueue(_venda(id: 'c1'));
      await fila.markConflicting('c1');

      final atencao = await fila.needingAttention();
      expect(atencao.map((op) => op.operationId), containsAll(['e1', 'c1']));
      expect(atencao.map((op) => op.operationId), isNot(contains('p1')));
    });
  });

  group('limpeza', () {
    test('não apaga o que sincronizou agora', () async {
      // Uma operação recém-sincronizada ainda explica ao operador o que houve.
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markSynced('op-1');

      expect(await fila.pruneSynced(), 0);
      expect(await fila.find('op-1'), isNotNull);
    });

    test('apaga o sincronizado antigo', () async {
      await fila.enqueue(_venda(id: 'op-1'));
      await fila.markSynced('op-1');

      expect(await fila.pruneSynced(keepFor: Duration.zero), 1);
      expect(await fila.find('op-1'), isNull);
    });

    test('nunca apaga o que não chegou ao servidor', () async {
      await fila.enqueue(_venda(id: 'pendente'));
      await fila.enqueue(_venda(id: 'erro'));
      await fila.markFailed('erro', 'x');
      await fila.enqueue(_venda(id: 'conflito'));
      await fila.markConflicting('conflito');

      expect(await fila.pruneSynced(keepFor: Duration.zero), 0);
      expect((await fila.summary()).outstanding, 3);
    });
  });

  group('estados', () {
    test('só pendente e erro voltam para a fila', () {
      expect(SyncStatus.pendente.shouldRetry, isTrue);
      expect(SyncStatus.erro.shouldRetry, isTrue);
      expect(SyncStatus.conflitante.shouldRetry, isFalse);
      expect(SyncStatus.sincronizado.shouldRetry, isFalse);
    });

    test('código desconhecido vira pendente, e não sincronizado', () {
      // Errar para o lado de reenviar é seguro: a idempotência do servidor
      // (RF36) impede duplicata. Errar para "sincronizado" perderia a venda.
      expect(SyncStatus.fromCode('COISA_NOVA'), SyncStatus.pendente);
      expect(SyncStatus.fromCode(null), SyncStatus.pendente);
    });
  });
}

/// A sincronização da fila (RF35, §13.10).
///
/// Cada desfecho aqui decide o que acontece com uma venda que já foi feita no
/// balcão. Errar para "sincronizado" perde a venda; errar para "erro" faz o
/// terminal insistir. O que os testes cobram é essa decisão, um caso por vez.
library;

import 'package:casa_das_bicicletas/core/failure.dart';
import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/sync_outcome.dart';
import 'package:casa_das_bicicletas/domain/repositories/sync_repository.dart';
import 'package:casa_das_bicicletas/domain/usecases/sync_pending_operations.dart';
import 'package:flutter_test/flutter_test.dart';

PendingOperation _operacao(String id, {DateTime? quando}) => PendingOperation(
      operationId: id,
      type: OperationType.saleCreate,
      payload: {'uuid': id},
      occurredAt: quando ?? DateTime.utc(2026, 9, 11, 14),
      status: SyncStatus.pendente,
    );

/// Fila em memória que registra o que foi pedido dela.
class _FilaFalsa implements SyncableQueue {
  _FilaFalsa(this.lote);

  List<PendingOperation> lote;

  final List<String> sincronizadas = [];
  final Map<String, int?> idsDoServidor = {};
  final Map<String, String> falhas = {};
  final Map<String, String?> conflitos = {};

  int lotesPedidos = 0;

  @override
  Future<List<PendingOperation>> nextBatch({int limit = 50}) async {
    lotesPedidos++;
    return lote.take(limit).toList();
  }

  @override
  Future<void> markSynced(String operationId, {int? serverId}) async {
    sincronizadas.add(operationId);
    idsDoServidor[operationId] = serverId;
  }

  @override
  Future<void> markFailed(String operationId, String error) async =>
      falhas[operationId] = error;

  @override
  Future<void> markConflicting(
    String operationId, {
    String? conflictId,
    String? error,
  }) async =>
      conflitos[operationId] = conflictId;
}

class _EnvioFalso implements SyncRepository {
  _EnvioFalso(this.response);

  final Result<List<SyncOutcome>> response;

  List<PendingOperation>? enviado;
  int chamadas = 0;

  @override
  Future<Result<List<SyncOutcome>>> push(
    List<PendingOperation> operations,
  ) async {
    chamadas++;
    enviado = operations;
    return response;
  }
}

void main() {
  group('fila vazia', () {
    test('não chama o servidor', () async {
      final envio = _EnvioFalso(const Ok(<SyncOutcome>[]));
      final usecase = SyncPendingOperations(
        queue: _FilaFalsa([]),
        sync: envio,
      );

      final resultado = await usecase();

      expect(envio.chamadas, 0);
      expect((resultado as Ok<SyncReport>).value.isEmpty, isTrue);
    });
  });

  group('operação aceita', () {
    test('sai da fila com o id do servidor', () async {
      final fila = _FilaFalsa([_operacao('op-1')]);
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: _EnvioFalso(
          const Ok([
            SyncOutcome(
              operationId: 'op-1',
              status: SyncStatus.sincronizado,
              serverId: 10490,
            ),
          ]),
        ),
      );

      final relatorio = ((await usecase()) as Ok<SyncReport>).value;

      expect(fila.sincronizadas, ['op-1']);
      expect(fila.idsDoServidor['op-1'], 10490);
      expect(relatorio.accepted, 1);
      expect(relatorio.needsAttention, isFalse);
    });

    test('manda o lote no formato do §3.9', () async {
      final envio = _EnvioFalso(
        const Ok([
          SyncOutcome(operationId: 'op-1', status: SyncStatus.sincronizado),
        ]),
      );
      final usecase = SyncPendingOperations(
        queue: _FilaFalsa([_operacao('op-1')]),
        sync: envio,
      );

      await usecase();

      final json = envio.enviado!.single.toSyncJson();
      expect(json['operation_id'], 'op-1');
      expect(json['type'], 'SALE_CREATE');
      expect(json['payload'], isA<Map<String, Object?>>());
      expect(json['occurred_at'], '2026-09-11T14:00:00.000Z');
    });
  });

  group('conflito', () {
    test('guarda o identificador e sai da fila de reenvio', () async {
      final fila = _FilaFalsa([_operacao('op-1')]);
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: _EnvioFalso(
          const Ok([
            SyncOutcome(
              operationId: 'op-1',
              status: SyncStatus.conflitante,
              conflictId: 'cf-uuid-1',
              message: 'Venda já confirmada',
            ),
          ]),
        ),
      );

      final relatorio = ((await usecase()) as Ok<SyncReport>).value;

      expect(fila.conflitos['op-1'], 'cf-uuid-1');
      expect(fila.sincronizadas, isEmpty);
      expect(relatorio.conflicting, 1);
      expect(relatorio.needsAttention, isTrue);
    });
  });

  group('um desfecho não arrasta os outros', () {
    test('uma entra, outra conflita, terceira falha', () async {
      // O §3.9 é explícito: operação recusada não interrompe o lote.
      final fila = _FilaFalsa([
        _operacao('ok'),
        _operacao('conflito'),
        _operacao('erro'),
      ]);
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: _EnvioFalso(
          const Ok([
            SyncOutcome(operationId: 'ok', status: SyncStatus.sincronizado),
            SyncOutcome(
              operationId: 'conflito',
              status: SyncStatus.conflitante,
              conflictId: 'cf-1',
            ),
            SyncOutcome(
              operationId: 'erro',
              status: SyncStatus.erro,
              message: 'Produto inativo',
            ),
          ]),
        ),
      );

      final relatorio = ((await usecase()) as Ok<SyncReport>).value;

      expect(relatorio.sent, 3);
      expect(relatorio.accepted, 1);
      expect(relatorio.conflicting, 1);
      expect(relatorio.failed, 1);
      expect(fila.sincronizadas, ['ok']);
      expect(fila.conflitos.keys, ['conflito']);
      expect(fila.falhas['erro'], 'Produto inativo');
    });
  });

  group('o que o servidor não respondeu', () {
    test('fica como falha, e nunca como sincronizada', () async {
      // Supor que foi aceita perderia a venda. Como falha ela volta na próxima
      // rodada, e a idempotência do servidor (RF36) impede duplicata.
      final fila = _FilaFalsa([_operacao('op-1'), _operacao('esquecida')]);
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: _EnvioFalso(
          const Ok([
            SyncOutcome(operationId: 'op-1', status: SyncStatus.sincronizado),
          ]),
        ),
      );

      final relatorio = ((await usecase()) as Ok<SyncReport>).value;

      expect(fila.sincronizadas, ['op-1']);
      expect(fila.falhas.keys, ['esquecida']);
      expect(relatorio.failed, 1);
    });
  });

  group('falha do lote inteiro', () {
    test('não marca ninguém, para não inflar a contagem de tentativas',
        () async {
      // Rede caiu no meio do envio: o problema não é das operações.
      final fila = _FilaFalsa([_operacao('op-1'), _operacao('op-2')]);
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: _EnvioFalso(const Err(NetworkFailure())),
      );

      final resultado = await usecase();

      expect(resultado, isA<Err<SyncReport>>());
      expect(fila.sincronizadas, isEmpty);
      expect(fila.falhas, isEmpty);
      expect(fila.conflitos, isEmpty);
    });
  });

  group('uma tentativa por vez', () {
    test('a segunda chamada simultânea não envia de novo', () async {
      // O gatilho é evento de rede, que dispara duas vezes quando o sinal
      // oscila; dois envios do mesmo lote embaralhariam a contagem.
      final envio = _EnvioFalso(
        const Ok([
          SyncOutcome(operationId: 'op-1', status: SyncStatus.sincronizado),
        ]),
      );
      final usecase = SyncPendingOperations(
        queue: _FilaFalsa([_operacao('op-1')]),
        sync: envio,
      );

      final primeira = usecase();
      final segunda = usecase();
      await Future.wait([primeira, segunda]);

      expect(envio.chamadas, 1);
    });

    test('depois de terminar, sincroniza de novo normalmente', () async {
      final envio = _EnvioFalso(
        const Ok([
          SyncOutcome(operationId: 'op-1', status: SyncStatus.sincronizado),
        ]),
      );
      final usecase = SyncPendingOperations(
        queue: _FilaFalsa([_operacao('op-1')]),
        sync: envio,
      );

      await usecase();
      expect(usecase.isRunning, isFalse);
      await usecase();

      expect(envio.chamadas, 2);
    });
  });

  group('tamanho do lote', () {
    test('respeita o limite configurado', () async {
      final fila = _FilaFalsa([
        for (var i = 0; i < 10; i++) _operacao('op-$i'),
      ]);
      final envio = _EnvioFalso(const Ok(<SyncOutcome>[]));
      final usecase = SyncPendingOperations(
        queue: fila,
        sync: envio,
        batchSize: 3,
      );

      await usecase();

      expect(envio.enviado, hasLength(3));
    });
  });
}

/// O contrato do `POST /sync/push/` na parte que o operador vê — OFF-007.
///
/// O servidor já escreve o motivo da recusa em cada resultado do lote
/// (`error.message`, §3.9). O terminal lia `message` no **topo** do resultado,
/// onde nunca houve nada, e gravava na fila a frase genérica "O servidor
/// recusou a operação" — deixando quem está no balcão sem saber se o problema
/// era o produto, a permissão ou a data.
///
/// O corpo usado aqui é o que a rota devolve de verdade, conferido contra
/// `apps/sync/services.py::_resultado`.
library;

import 'package:casa_das_bicicletas/core/result.dart';
import 'package:casa_das_bicicletas/data/repositories/sync_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/pending_operation.dart';
import 'package:casa_das_bicicletas/domain/entities/sync_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _idDaOperacao = '11111111-1111-4111-8111-111111111111';

PendingOperation _operacaoNaFila() => PendingOperation(
      operationId: _idDaOperacao,
      type: OperationType.saleCreate,
      payload: const {'payment_method': 'PIX', 'items': <Object?>[]},
      occurredAt: DateTime.utc(2026, 10, 9, 14),
      status: SyncStatus.pendente,
    );

/// Um resultado de lote como o servidor o monta.
Map<String, Object?> _resultado({
  required String status,
  Map<String, Object?>? error,
  int? serverId,
  String? conflictId,
}) =>
    {
      'results': [
        {
          'operation_id': _idDaOperacao,
          'status': status,
          'server_id': serverId,
          'entity_type': serverId == null ? null : 'sale',
          if (error != null) 'error': error,
          if (conflictId != null) 'conflict_id': conflictId,
        }
      ],
    };

void main() {
  late SyncRepositoryImpl repository;

  Future<void> preparar(RecordingTransport http) async {
    final deps = buildTestDependencies(transport: http);
    await deps.session.saveConfiguration(deviceId: 'M10-0001', storeId: 1);
    repository = SyncRepositoryImpl(deps.apiClient);
  }

  Future<SyncOutcome> enviar(Map<String, Object?> corpo) async {
    await preparar(RecordingTransport((_) => jsonResponse(corpo)));
    final resultado = await repository.push([_operacaoNaFila()]);
    return (resultado as Ok<List<SyncOutcome>>).value.single;
  }

  test('o motivo da recusa chega ao terminal, com a frase do servidor', () async {
    final desfecho = await enviar(
      _resultado(
        status: 'ERRO_SINCRONIZACAO',
        error: const {
          'code': 'VALIDATION_ERROR',
          'message': 'Produto 10 inativo ou de outra loja.',
        },
      ),
    );

    expect(desfecho.status, SyncStatus.erro);
    expect(desfecho.message, 'Produto 10 inativo ou de outra loja.');
  });

  test('o motivo do conflito também, com o id para decidir', () async {
    final desfecho = await enviar(
      _resultado(
        status: 'CONFLITANTE',
        conflictId: '42',
        error: const {
          'code': 'SYNC_CONFLICT',
          'message': 'Hora do evento fora da janela: 400 dias atrás.',
        },
      ),
    );

    expect(desfecho.status, SyncStatus.conflitante);
    expect(desfecho.message, contains('fora da janela'));
    expect(desfecho.conflictId, '42');
  });

  test('operação aceita não inventa mensagem', () async {
    final desfecho = await enviar(_resultado(status: 'SINCRONIZADO', serverId: 10490));

    expect(desfecho.accepted, isTrue);
    expect(desfecho.serverId, 10490);
    expect(desfecho.message, isNull);
  });

  test('o lote não leva chave de idempotência — OFF-012', () async {
    // Ia uma chave nova a cada envio, com um comentário prometendo que ela
    // 'evita o reprocessamento no servidor'. Chave nova nunca casa com nada, e
    // `POST /sync/push/` não é decorada com `@idempotent`: o cabeçalho era
    // ignorado do outro lado. Quem protege é o `operation_id` (RF36).
    final transporte = RecordingTransport(
      (_) => jsonResponse(_resultado(status: 'SINCRONIZADO', serverId: 1)),
    );
    await preparar(transporte);

    await repository.push([_operacaoNaFila()]);

    expect(
      transporte.lastRequest.headers.containsKey('X-Idempotency-Key'),
      isFalse,
    );
  });

  test('recusa sem corpo de erro não quebra o mapeamento', () async {
    // O servidor sempre manda o `error` numa recusa, mas o terminal não pode
    // depender disso para não perder o lote inteiro: a frase genérica da fila
    // cobre o caso.
    final desfecho = await enviar(_resultado(status: 'ERRO_SINCRONIZACAO'));

    expect(desfecho.status, SyncStatus.erro);
    expect(desfecho.message, isNull);
  });
}
